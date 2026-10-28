#define _DEFAULT_SOURCE

#include "power/rtc_wake.h"
#include "models/wake_profiles.h"

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* Select exactly one controller matching this independently identified model.
 * Never choose the first rtcN, and never retry on a different device after an error. */
int ugreenctl_rtc_select_at(const char *root, const struct ugreenctl_rtc_profile *profile,
                           char *path, size_t path_size, char *error, size_t error_size)
{
    char directory_path[PATH_MAX], candidate[PATH_MAX], attribute[PATH_MAX], line[256];
    DIR *directory;
    struct dirent *entry;
    unsigned matches = 0;
    if (!root || !profile || !profile->rtc_name || !path || !path_size) return -EINVAL;
    if (snprintf(directory_path,sizeof(directory_path),"%s/class/rtc",root)>=(int)sizeof(directory_path)) return -ENAMETOOLONG;
    directory=opendir(directory_path);
    if (!directory) {
        (void)snprintf(error,error_size,"cannot inspect RTC devices: %s",strerror(errno));
        return -errno;
    }
    path[0]=0;
    while ((entry=readdir(directory))) {
        const char *digit;
        FILE *stream;
        struct stat status;
        int good=0;
        size_t name_length=strlen(profile->rtc_name);
        if (strncmp(entry->d_name,"rtc",3) || !entry->d_name[3]) continue;
        for (digit=entry->d_name+3; *digit && isdigit((unsigned char)*digit); ++digit) {}
        if (*digit) continue;
        if (snprintf(candidate,sizeof(candidate),"%s/%s",directory_path,entry->d_name)>=(int)sizeof(candidate) ||
            snprintf(attribute,sizeof(attribute),"%s/name",candidate)>=(int)sizeof(attribute)) continue;
        stream=fopen(attribute,"r");
        if (!stream) continue;
        if (fgets(line,sizeof(line),stream)) {
            line[strcspn(line,"\r\n")]=0;
            good=!strncmp(line,profile->rtc_name,name_length) &&
                (line[name_length]==0 || line[name_length]==' ');
        }
        (void)fclose(stream);
        if (!good) continue;
        if (profile->rtc_of_path) {
            good=0;
            if (snprintf(attribute,sizeof(attribute),"%s/device/uevent",candidate)>=(int)sizeof(attribute)) continue;
            stream=fopen(attribute,"r");
            if (!stream) continue;
            while (fgets(line,sizeof(line),stream)) {
                line[strcspn(line,"\r\n")]=0;
                if (!strncmp(line,"OF_FULLNAME=",12) && !strcmp(line+12,profile->rtc_of_path)) good=1;
            }
            (void)fclose(stream);
            if (!good) continue;
        }
        if (snprintf(attribute,sizeof(attribute),"%s/wakealarm",candidate)>=(int)sizeof(attribute) ||
            lstat(attribute,&status) || !S_ISREG(status.st_mode)) continue;
        ++matches;
        if (strlen(attribute)>=path_size) { (void)closedir(directory); return -ENAMETOOLONG; }
        strcpy(path,attribute);
    }
    (void)closedir(directory);
    if (matches!=1) {
        path[0]=0;
        (void)snprintf(error,error_size,"expected one %s RTC wakealarm for %s; found %u (unknown/ambiguous hardware)",
                       profile->rtc_name,profile->product,matches);
        return -ENODEV;
    }
    return 0;
}

static int write_wakealarm(const char *path, const char *value,
                           char *error, size_t error_size)
{
    int fd;
    size_t length = strlen(value);
    ssize_t written;

    fd = open(path, O_WRONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) {
        (void)snprintf(error, error_size, "cannot open RTC wakealarm: %s", strerror(errno));
        return -errno;
    }
    written = write(fd, value, length);
    if (written < 0 || (size_t)written != length) {
        int saved_errno = written < 0 ? errno : EIO;

        (void)close(fd);
        (void)snprintf(error, error_size, "cannot write RTC wakealarm: %s", strerror(saved_errno));
        return -saved_errno;
    }
    (void)close(fd);
    return 0;
}

int ugreenctl_rtc_wake_parse(const char *value, time_t *epoch,
                             char *error, size_t error_size)
{
    const char *cursor;
    char *end;
    long long parsed;

    if (value == NULL || epoch == NULL) {
        (void)snprintf(error, error_size, "RTC wakealarm output is required");
        return -EINVAL;
    }
    cursor = value;
    while (isspace((unsigned char)*cursor)) {
        ++cursor;
    }
    if (*cursor == '\0') {
        *epoch = 0;
        return 0;
    }
    errno = 0;
    parsed = strtoll(cursor, &end, 10);
    while (isspace((unsigned char)*end)) {
        ++end;
    }
    if (errno != 0 || end == cursor || *end != '\0') {
        (void)snprintf(error, error_size, "RTC wakealarm returned an invalid value");
        return -EIO;
    }
    if (parsed < 0 || (unsigned long long)parsed > (unsigned long long)LLONG_MAX) {
        (void)snprintf(error, error_size, "RTC wakealarm returned an out-of-range value");
        return -ERANGE;
    }
    if ((long long)(time_t)parsed != parsed) return -ERANGE;
    *epoch = (time_t)parsed;
    return 0;
}

static int read_alarm(const char *path, time_t *epoch, char *error, size_t error_size)
{
    char value[64];
    int fd=open(path,O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    ssize_t count;
    if (fd<0) { (void)snprintf(error,error_size,"cannot read RTC wakealarm: %s",strerror(errno)); return -errno; }
    count=read(fd,value,sizeof(value)-1);
    if (count<0) { int saved=errno; (void)close(fd); return -saved; }
    (void)close(fd);
    if ((size_t)count==sizeof(value)-1) return -EOVERFLOW;
    value[count]=0;
    return ugreenctl_rtc_wake_parse(value,epoch,error,error_size);
}

int ugreenctl_rtc_wake_read(const struct ugreenctl_rtc_profile *profile, time_t *epoch,
                           char *error, size_t error_size)
{
    char path[PATH_MAX];
    int result=ugreenctl_rtc_select_at("/sys",profile,path,sizeof(path),error,error_size);
    return result ? result : read_alarm(path,epoch,error,error_size);
}

int ugreenctl_rtc_validate_epoch(const struct ugreenctl_rtc_profile *profile, time_t epoch,
                                time_t now, char *error, size_t error_size)
{
    if (!profile || !profile->resolution_seconds || now==(time_t)-1 || epoch<=now || epoch-now<=60) {
        (void)snprintf(error,error_size,"RTC time must be more than 60 seconds in the future"); return -EINVAL;
    }
    if (epoch % profile->resolution_seconds) {
        (void)snprintf(error,error_size,"this RTC requires %u-second aligned epochs; no silent rounding",
                       profile->resolution_seconds); return -EINVAL;
    }
    return 0;
}

/* Caller holds the RTC process lock and has rechecked machine identity.
 * Keep one path for clear, set and readback; clearing failure stops the write. */
static int update_alarm(const struct ugreenctl_rtc_profile *profile, time_t epoch,
                        char *error, size_t error_size)
{
    char path[PATH_MAX],value[64];
    time_t observed=-1;
    int result=ugreenctl_rtc_select_at("/sys",profile,path,sizeof(path),error,error_size);
    if (result) return result;
    if (epoch) {
        char clock_path[PATH_MAX];
        time_t rtc_now, system_now;
        size_t prefix=strlen(path)-strlen("wakealarm");
        if (snprintf(clock_path,sizeof(clock_path),"%.*ssince_epoch",(int)prefix,path)>=(int)sizeof(clock_path))
            return -ENAMETOOLONG;
        result=read_alarm(clock_path,&rtc_now,error,error_size);
        if (result) return result;
        system_now=time(NULL);
        /* sysfs alarm epochs use the RTC's time base. Do not silently schedule
         * a Unix timestamp on a LOCAL or unsynchronised hardware clock. */
        if (system_now==(time_t)-1 || rtc_now<=0 ||
            (rtc_now>system_now ? rtc_now-system_now : system_now-rtc_now)>5) {
            (void)snprintf(error,error_size,"RTC clock differs from system UTC or is unknown; alarm unchanged (check RTC time base/synchronisation)");
            return -EINVAL;
        }
    }
    result=read_alarm(path,&observed,error,error_size);
    if (result) return result;
    result=write_wakealarm(path,"0",error,error_size);
    if (result) return result;
    result=read_alarm(path,&observed,error,error_size);
    if (result) return result;
    if (observed!=0) {
        (void)snprintf(error,error_size,"RTC alarm clear readback mismatch; stopped"); return -EIO;
    }
    if (!epoch) return 0;
    (void)snprintf(value,sizeof(value),"%lld",(long long)epoch);
    result=write_wakealarm(path,value,error,error_size);
    if (result) return result;
    result=read_alarm(path,&observed,error,error_size);
    if (result) return result;
    if (observed!=epoch) {
        (void)snprintf(error,error_size,"RTC alarm readback mismatch; state not confirmed"); return -EIO;
    }
    return 0;
}
int ugreenctl_rtc_wake_clear(const struct ugreenctl_rtc_profile *profile, char *error, size_t error_size)
{
    return update_alarm(profile,0,error,error_size);
}
int ugreenctl_rtc_wake_set(const struct ugreenctl_rtc_profile *profile, time_t epoch,
                          char *error, size_t error_size)
{
    int result=ugreenctl_rtc_validate_epoch(profile,epoch,time(NULL),error,error_size);
    return result ? result : update_alarm(profile,epoch,error,error_size);
}
