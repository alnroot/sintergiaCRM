// The favicon <link> hrefs carry a ?v= cache-buster (see vueapp.html.erb).
// Favicons are served with a one-year max-age, so rebuilding a bare URL here
// would swap in whatever the browser already has cached under that name —
// which, right after a rebrand, is the previous icon. Carry the query string
// across so the badge swap keeps pointing at the current version.
const queryOf = href => {
  const index = href.indexOf('?');
  return index === -1 ? '' : href.slice(index);
};

export const showBadgeOnFavicon = () => {
  const favicons = document.querySelectorAll('.favicon');

  favicons.forEach(favicon => {
    const newFileName = `/favicon-badge-${favicon.sizes[[0]]}.png${queryOf(favicon.href)}`;
    favicon.href = newFileName;
  });
};

export const initFaviconSwitcher = () => {
  const favicons = document.querySelectorAll('.favicon');

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      favicons.forEach(favicon => {
        const oldFileName = `/favicon-${favicon.sizes[[0]]}.png${queryOf(favicon.href)}`;
        favicon.href = oldFileName;
      });
    }
  });
};
