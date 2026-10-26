#!/usr/bin/env python3
"""Optional Linux/Python 3 startup-policy persistence; hardware stays in ugreenctl.

State is an administrator's desired policy, never a cached hardware readback.
No writes or backend execution occur without BOTH --force and --apply.  This
helper does not install/enable a service, modify firmware, or access registers.
"""

import argparse
import contextlib
import json
import os
import secrets
import stat
import subprocess
import sys


SCHEMA_VERSION = 1
MAX_STATE_BYTES = 4096
MAX_DMI_BYTES = 256
STATE_FILE = "desired-policy.json"
LOCK_FILE = "startup.lock"
POLICIES = ("on", "off", "restore")
IDENTITY_FIELDS = ("product_name", "product_version", "board_version",
                   "bios_vendor", "bios_version", "bios_date")


class StartupError(Exception):
    def __init__(self, message, hardware_written=False, persistence_uncertain=False,
                 hardware_write_attempted=False):
        super().__init__(message)
        self.hardware_written = hardware_written
        self.persistence_uncertain = persistence_uncertain
        self.hardware_write_attempted = hardware_write_attempted or hardware_written


def _text(value, name, allow_empty=True):
    try:
        byte_length = len(value.encode("utf-8")) if type(value) is str else MAX_DMI_BYTES + 1
    except UnicodeError as error:
        raise StartupError("invalid identity field: " + name) from error
    if (type(value) is not str or byte_length > MAX_DMI_BYTES or
            (not allow_empty and not value) or
            any(ord(c) < 32 or ord(c) == 127 for c in value)):
        raise StartupError("invalid identity field: " + name)
    return value


def validate_identity(identity):
    if type(identity) is not dict or set(identity) != set(IDENTITY_FIELDS):
        raise StartupError("state requires the exact DMI/BIOS identity fields")
    return {name: _text(identity[name], name, name != "product_name")
            for name in IDENTITY_FIELDS}


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise StartupError("duplicate JSON key: " + key)
        result[key] = value
    return result


def decode_state(data):
    if not data or len(data) > MAX_STATE_BYTES:
        raise StartupError("state is empty or exceeds 4096 bytes")
    try:
        record = json.loads(data.decode("utf-8"), object_pairs_hook=_unique_object,
                            parse_constant=lambda value: _reject_constant(value))
    except (UnicodeError, ValueError, RecursionError) as error:
        raise StartupError("invalid state JSON") from error
    if (type(record) is not dict or
            set(record) != {"schema_version", "desired_policy", "identity"} or
            type(record["schema_version"]) is not int or
            record["schema_version"] != SCHEMA_VERSION):
        raise StartupError("unsupported or malformed startup state schema")
    if type(record["desired_policy"]) is not str or record["desired_policy"] not in POLICIES:
        raise StartupError("invalid saved desired_policy")
    record["identity"] = validate_identity(record["identity"])
    return record


def _reject_constant(value):
    raise StartupError("non-finite JSON number is not allowed: " + value)


def _absolute_parts(path):
    # Do not normalize away a symlink/../ component before checking it.
    if type(path) is not str or not path.startswith("/") or "\x00" in path:
        raise StartupError("an absolute Linux path is required")
    parts = path.split("/")[1:]
    if not parts or any(part in ("", ".", "..") for part in parts):
        raise StartupError("path must contain only explicit nonempty components")
    return parts


def _check_directory(info, private=False):
    if (not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or
            info.st_mode & (0o077 if private else 0o022)):
        raise StartupError("state path must be root-owned and not writable by others; "
                           "the state directory must be private (0700)")


def _check_regular(info, label):
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or
            info.st_nlink != 1 or stat.S_IMODE(info.st_mode) not in (0o400, 0o600)):
        raise StartupError(label + " must be a root-owned regular single-link file (0600/0400)")


class LinuxStateStore:
    """All state traversal/mutation is relative to checked directory descriptors."""

    def __init__(self, path, os_api=os, flock=None):
        self.path = path
        self.os = os_api
        self.flock = flock

    @contextlib.contextmanager
    def open(self, create=False):
        parts = _absolute_parts(self.path)
        api = self.os
        flags = api.O_RDONLY | api.O_DIRECTORY | api.O_NOFOLLOW | api.O_CLOEXEC
        fd = None
        try:
            fd = api.open("/", flags)
            _check_directory(api.fstat(fd))
            for part in parts:
                try:
                    child = api.open(part, flags, dir_fd=fd)
                except FileNotFoundError:
                    if not create:
                        api.close(fd)
                        fd = None
                        yield None
                        return
                    try:
                        api.mkdir(part, 0o700, dir_fd=fd)
                        api.fsync(fd)
                    except FileExistsError:
                        pass
                    child = api.open(part, flags, dir_fd=fd)
                api.close(fd)
                fd = child
                _check_directory(api.fstat(fd))
            _check_directory(api.fstat(fd), private=True)
            yield StateDirectory(fd, api, self.flock)
        except OSError as error:
            raise StartupError("unsafe or inaccessible state path: " + str(error)) from error
        finally:
            if fd is not None:
                api.close(fd)


class StateDirectory:
    def __init__(self, fd, os_api, flock):
        self.fd, self.os, self.flock = fd, os_api, flock

    @contextlib.contextmanager
    def locked(self):
        api = self.os
        if self.flock is None:
            import fcntl
            lock = fcntl.flock
            operation = fcntl.LOCK_EX | fcntl.LOCK_NB
            unlock = fcntl.LOCK_UN
        else:
            # Injection is a Python API for tests, never a CLI/environment bypass.
            lock, operation, unlock = self.flock
        fd = api.open(LOCK_FILE, api.O_RDWR | api.O_CREAT | api.O_NOFOLLOW |
                      api.O_CLOEXEC | api.O_NONBLOCK, 0o600, dir_fd=self.fd)
        acquired = False
        try:
            info = api.fstat(fd)
            _check_regular(info, "lock")
            if stat.S_IMODE(info.st_mode) != 0o600:
                raise StartupError("lock must have mode 0600")
            try:
                lock(fd, operation)
                acquired = True
            except BlockingIOError as error:
                raise StartupError("another startup-policy operation holds the lock") from error
            yield
        finally:
            try:
                if acquired:
                    lock(fd, unlock)
            finally:
                api.close(fd)

    def load(self):
        api = self.os
        try:
            fd = api.open(STATE_FILE, api.O_RDONLY | api.O_NOFOLLOW | api.O_CLOEXEC |
                          api.O_NONBLOCK, dir_fd=self.fd)
        except FileNotFoundError:
            return None
        try:
            info = api.fstat(fd)
            _check_regular(info, "state")
            if info.st_size <= 0 or info.st_size > MAX_STATE_BYTES:
                raise StartupError("state is empty or exceeds 4096 bytes")
            data = bytearray()
            while len(data) <= MAX_STATE_BYTES:
                chunk = api.read(fd, MAX_STATE_BYTES + 1 - len(data))
                if not chunk:
                    break
                data.extend(chunk)
            after = api.fstat(fd)
            _check_regular(after, "state")
            if after.st_size != len(data) or info.st_size != after.st_size:
                raise StartupError("state changed while being read")
            return decode_state(bytes(data))
        finally:
            api.close(fd)

    def save(self, record):
        api = self.os
        data = (json.dumps(record, ensure_ascii=True, sort_keys=True,
                           separators=(",", ":")) + "\n").encode("utf-8")
        decode_state(data)
        # Refuse an unsafe replacement target even if it changed during backend IO.
        self.load()
        name = ".startup-" + secrets.token_hex(16) + ".tmp"
        fd = None
        replaced = False
        try:
            fd = api.open(name, api.O_WRONLY | api.O_CREAT | api.O_EXCL |
                          api.O_NOFOLLOW | api.O_CLOEXEC, 0o600, dir_fd=self.fd)
            _check_regular(api.fstat(fd), "temporary state")
            offset = 0
            while offset < len(data):
                written = api.write(fd, data[offset:])
                if written <= 0:
                    raise OSError("short state write")
                offset += written
            api.fsync(fd)
            _check_regular(api.fstat(fd), "temporary state")
            api.close(fd)
            fd = None
            api.replace(name, STATE_FILE, src_dir_fd=self.fd, dst_dir_fd=self.fd)
            replaced = True
            api.fsync(self.fd)
        except (OSError, StartupError) as error:
            raise StartupError("hardware was written, but saving the desired policy failed: "
                               + str(error), hardware_written=True,
                               persistence_uncertain=replaced) from error
        finally:
            if fd is not None:
                api.close(fd)
            if not replaced:
                try:
                    api.unlink(name, dir_fd=self.fd)
                except OSError:
                    # Preserve the actual persistence failure; any leftover is a
                    # private 0600 temporary file, never an accepted state record.
                    pass


class LinuxRuntime:
    def require_root(self):
        if sys.platform != "linux":
            raise StartupError("this optional Python helper runs only on Linux")
        if os.geteuid() != 0:
            raise StartupError("startup state operations require root")

    def identity(self):
        identity = {}
        for field in IDENTITY_FIELDS:
            # Fixed real sysfs path. No environment, --model, or alternate sysfs root.
            with open("/sys/class/dmi/id/" + field, "rb") as source:
                data = source.read(MAX_DMI_BYTES + 2)
            if data.endswith(b"\n"):
                data = data[:-1]
            try:
                identity[field] = data.decode("utf-8")
            except UnicodeError as error:
                raise StartupError("DMI identity is not UTF-8") from error
        return validate_identity(identity)


class Backend:
    def __init__(self, binary, plugin_dir=None, runner=subprocess.run):
        _absolute_parts(binary)
        if plugin_dir is not None:
            _absolute_parts(plugin_dir)
        self.prefix = [binary] + (["--plugin-dir", plugin_dir] if plugin_dir else [])
        self.runner = runner

    def _run(self, tail, write=False):
        command = self.prefix + (["--force", "--apply"] if write else []) + tail
        try:
            result = self.runner(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 timeout=20, check=False, cwd="/", shell=False,
                                 env={"PATH": "/usr/sbin:/usr/bin:/sbin:/bin",
                                      "LC_ALL": "C", "LANG": "C"})
        except (OSError, subprocess.TimeoutExpired) as error:
            raise StartupError("ugreenctl execution failed: " + str(error),
                               hardware_written=None if write else False,
                               hardware_write_attempted=write) from error
        if result.returncode != 0:
            raise StartupError("ugreenctl rejected the operation (exit " +
                               str(result.returncode) + ")",
                               hardware_written=None if write else False,
                               hardware_write_attempted=write)
        return result.stdout

    def get(self, allow_unknown=False):
        data = self._run(["power", "startup", "get"])
        values = POLICIES + (("unknown",) if allow_unknown else ())
        for value in values:
            if data in (value.encode("ascii"), (value + "\n").encode("ascii")):
                return value
        raise StartupError("ugreenctl returned an unknown or malformed startup policy")

    def set(self, policy):
        self._run(["power", "startup", "set", policy], write=True)


def execute(command, policy, force, apply, store, runtime, backend=None):
    """Testable coordinator. Production implementations have no hardware overrides."""
    runtime.require_root()
    if force != apply:
        raise StartupError("writes require --force and --apply together")
    writing = force and apply and command != "show"
    if command == "set":
        policy = "restore" if policy == "last" else policy
        if policy not in POLICIES:
            raise StartupError("set requires on, off, restore, or last")
    elif command not in ("apply", "show") or policy is not None:
        raise StartupError("invalid command or policy")
    if writing and backend is None:
        raise StartupError("--binary requires an absolute ugreenctl executable path")
    result = {"schema_version": SCHEMA_VERSION, "command": command,
              "dry_run": not writing, "hardware_written": False,
              "hardware_write_attempted": False,
              "state_saved": False, "current_hardware_policy": "not_read"}
    with store.open(create=writing and command == "set") as directory:
        saved = directory.load() if directory is not None else None
        if saved is None and command != "set":
            return dict(result, configured=False, desired_policy=None,
                        action="no_saved_policy")
        if command == "show" or not writing:
            identity = validate_identity(runtime.identity())
            matches = saved is None or saved["identity"] == identity
            if command == "apply" and not matches:
                raise StartupError("DMI/BIOS identity changed; administrator must explicitly set again")
            return dict(result, configured=saved is not None,
                        desired_policy=saved["desired_policy"] if saved else None,
                        requested_policy=policy if command == "set" else None,
                        identity_matches=matches, observed_identity=identity,
                        saved_identity=saved["identity"] if saved else None,
                        action="show_saved_desire" if command == "show" else "would_set_and_verify")
        with directory.locked():
            # Re-read after taking the process lock; another administrator may have set.
            saved = directory.load()
            if saved is None and command == "apply":
                return dict(result, configured=False, desired_policy=None,
                            action="no_saved_policy")
            identity = validate_identity(runtime.identity())
            if command == "apply" and saved["identity"] != identity:
                raise StartupError("DMI/BIOS identity changed; administrator must explicitly set again")
            wanted = policy if command == "set" else saved["desired_policy"]
            # A BIOS may overwrite both bits with an unknown encoding. That is a valid
            # reason to restore, unlike a failed/garbled read or an unsupported backend.
            backend.get(allow_unknown=True)
            if validate_identity(runtime.identity()) != identity:
                raise StartupError("DMI/BIOS identity changed before the write")
            backend.set(wanted)
            try:
                readback = backend.get()
                if readback != wanted:
                    raise StartupError("startup policy readback does not match the desired policy")
                if validate_identity(runtime.identity()) != identity:
                    raise StartupError("DMI/BIOS identity changed after the write")
                if command == "set":
                    directory.save({"schema_version": SCHEMA_VERSION,
                                    "desired_policy": wanted, "identity": identity})
            except (StartupError, OSError) as error:
                raise StartupError("hardware was written but the operation was not confirmed/saved: "
                                   + str(error), hardware_written=True,
                                   persistence_uncertain=getattr(error, "persistence_uncertain", False)) from error
            return dict(result, configured=True, desired_policy=wanted,
                        hardware_written=True, state_saved=command == "set",
                        hardware_write_attempted=True,
                        current_hardware_policy=readback, action="set_and_verified")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("set", "apply", "show"))
    parser.add_argument("policy", nargs="?", choices=POLICIES + ("last",))
    parser.add_argument("--binary", help="absolute path to the existing ugreenctl executable")
    parser.add_argument("--plugin-dir", help="optional absolute plugin directory")
    parser.add_argument("--state-dir", default="/var/lib/ugreenctl/startup")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args(argv)
    try:
        backend = Backend(args.binary, args.plugin_dir) if args.binary else None
        if args.plugin_dir and not args.binary:
            raise StartupError("--plugin-dir requires --binary")
        result = execute(args.command, args.policy, args.force, args.apply,
                         LinuxStateStore(args.state_dir), LinuxRuntime(), backend)
        print(json.dumps(result, ensure_ascii=True, sort_keys=True))
        return 0
    except (StartupError, OSError) as error:
        print(json.dumps({"error": str(error), "hardware_written":
                          getattr(error, "hardware_written", False),
                          "hardware_write_attempted":
                          getattr(error, "hardware_write_attempted", False),
                          "hardware_may_have_changed":
                          getattr(error, "hardware_write_attempted", False),
                          "state_saved": False, "persistence_uncertain":
                          getattr(error, "persistence_uncertain", False)}, sort_keys=True),
              file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
