export const readmeRepositoryUrl = 'https://github.com/BearHero520/UGreen-Control';
const readmeImageBase = 'https://raw.githubusercontent.com/BearHero520/UGreen-Control/main/';

export function readmeHref(value: string) {
  if (/^(https?:|#)/i.test(value)) return value;
  return `${readmeRepositoryUrl}/blob/main/${value.replace(/^\.\//, '')}`;
}

export function readmeImageSrc(value: string): string | null {
  try {
    const url = new URL(value, readmeImageBase);
    return /^https?:$/.test(url.protocol) ? url.href : null;
  } catch {
    return null;
  }
}

export type ReadmeInlineToken =
  | { kind: 'text' | 'strong' | 'code'; text: string }
  | { kind: 'link'; text: string; href: string }
  | { kind: 'image'; text: string; src: string };

export function readmeInlineTokens(text: string): ReadmeInlineToken[] {
  return text.split(/(\*\*[^*]+\*\*|`[^`]+`|!\[[^\]]*\]\([^)]+\)|\[[^\]]+\]\([^)]+\))/g)
    .filter(Boolean)
    .map((token): ReadmeInlineToken => {
      if (token.startsWith('**') && token.endsWith('**')) return { kind: 'strong', text: token.slice(2, -2) };
      if (token.startsWith('`') && token.endsWith('`')) return { kind: 'code', text: token.slice(1, -1) };
      const image = token.match(/^!\[([^\]]*)\]\(([^)]+)\)$/);
      if (image) {
        const src = readmeImageSrc(image[2]);
        return src ? { kind: 'image', text: image[1], src } : { kind: 'text', text: token };
      }
      const link = token.match(/^\[([^\]]+)\]\(([^)]+)\)$/);
      if (link) return { kind: 'link', text: link[1], href: readmeHref(link[2]) };
      return { kind: 'text', text: token };
    });
}
