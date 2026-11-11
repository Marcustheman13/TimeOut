# Share links that open the app

Today a friend or team link (`https://…/?invite=name&code=…`) opens the website. On an iPhone the invite sheet has an
**Open in the TimeOut app** button that uses the `timeout://invite?…` address the app already understands.

Making the link open the app by default needs the app on the App Store. Two steps once it is published:

## 1. Open the app automatically from the website (quick)
In [`social.js`](../../TimeOut%20-%20Web/js/social.js) set:

```js
TO.appLink = { autoOpen: true, appStoreUrl: 'https://apps.apple.com/app/idYOURAPPID' };
```

An iPhone that opens a share link then jumps straight into the app. If the app isn't installed, the page stays on the
website and offers a **Get the app from the App Store** button in the invite sheet. Leave `autoOpen` false until the app is public: Safari
shows an error for `timeout://` when nothing handles it.

## 2. Universal Links (proper fix, needs your own domain)
GitHub Pages can't serve the required `/.well-known/apple-app-site-association` file for a `github.io/TimeOut` path, so
this needs a domain you control (for example `timeout-app.com`) pointing at the site.

1. Host `https://YOUR-DOMAIN/.well-known/apple-app-site-association` (no extension, `application/json`):
   ```json
   { "applinks": { "details": [ { "appIDs": ["TEAMID.com.marcuswilliams.staketime"], "components": [ { "/": "/*", "?": { "invite": "?*" } } ] } ] } }
   ```
2. In Xcode → Signing & Capabilities → add **Associated Domains** with `applinks:YOUR-DOMAIN`.
3. In the app, handle `https` links the same way as `timeout://invite` (`onOpenURL` in `TimeOutApp.swift` already parses
   the query), then point the share links (`friendLink` / `teamLink` on both platforms) at the new domain.
