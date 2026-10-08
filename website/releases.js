// Keep the static, verified download as a fallback when GitHub is unavailable.
(function () {
  'use strict';
  var controller = new AbortController();
  var timeout = setTimeout(function () { controller.abort(); }, 5000);
  fetch('https://api.github.com/repos/DeaglePC/MonitorX/releases/latest', {
    signal: controller.signal,
    headers: { Accept: 'application/vnd.github+json' }
  })
    .then(function (response) {
      if (!response.ok) throw new Error('Release unavailable');
      return response.json();
    })
    .then(function (release) {
      if (release.draft || release.prerelease || !Array.isArray(release.assets)) return;
      var asset = release.assets.find(function (item) {
        return /^MonitorX-[0-9][^/]*\.dmg$/.test(item.name) &&
          typeof item.browser_download_url === 'string' &&
          item.browser_download_url.startsWith('https://github.com/DeaglePC/MonitorX/releases/download/');
      });
      if (!asset) return;
      document.querySelectorAll('[data-release-download]').forEach(function (link) {
        link.href = asset.browser_download_url;
      });
      if (typeof release.tag_name === 'string') {
        document.querySelectorAll('[data-release-version]').forEach(function (label) {
          label.textContent = release.tag_name;
        });
      }
    })
    .catch(function () { /* The original download links remain usable. */ })
    .finally(function () { clearTimeout(timeout); });
})();
