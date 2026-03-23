# IT Tools — M365 Admin Hub

Browser-based Microsoft 365 admin utilities. Sign in with your work account — no scripts, no installations, no elevated permissions beyond what each tool needs.

## Live tools

| Tool | Description | Permissions required |
|---|---|---|
| [License Audit](tools/license-audit/) | Find inactive M365 license holders and surface recoverable seats | `User.Read.All`, `Directory.Read.All`, `AuditLog.Read.All` |
| [Group Import](tools/group-import/) | Bulk-add users to an Entra ID security group from a CSV | `User.Read.All`, `Group.ReadWrite.All`, `GroupMember.ReadWrite.All`, `Directory.Read.All` |

## Repository structure

```
it-tools/
├── index.html                      ← Hub landing page
├── shared/
│   ├── auth.js                     ← MSAL auth + Microsoft Graph helpers (shared by all tools)
│   └── styles.css                  ← Design system tokens + shared component styles
└── tools/
    ├── license-audit/
    │   └── index.html
    └── group-import/
        └── index.html
```

Each new tool goes in `tools/<tool-name>/index.html` and links to `../../shared/auth.js` and `../../shared/styles.css`. That's it.

## Setup — Entra ID app registration

All tools share **one app registration**. You only need to set this up once.

1. Go to [portal.azure.com](https://portal.azure.com) → **Entra ID** → **App registrations** → **New registration**
2. Name it something like `IT Tools (GitHub Pages)`
3. Under **Authentication → Single-page application**, add this redirect URI:
   ```
   https://<your-github-username>.github.io/it-tools/
   ```
4. Under **API permissions**, add the following Microsoft Graph **delegated** permissions and grant admin consent:
   - `User.Read`
   - `User.Read.All`
   - `Directory.Read.All`
   - `AuditLog.Read.All`
   - `Group.ReadWrite.All`
   - `GroupMember.ReadWrite.All`
5. Copy the **Application (client) ID** and update `CLIENT_ID` in `shared/auth.js`
6. Update `TENANT_ID` in `shared/auth.js` to your tenant ID

> **Note:** Each tool sub-path (e.g. `/it-tools/tools/license-audit/`) also needs to be added as a redirect URI in the app registration. MSAL uses the current page URL as the redirect URI, so each tool registers itself automatically — you just need to whitelist the paths.

## Adding a new tool

1. Create `tools/<your-tool-name>/index.html`
2. Add these two lines in `<head>`:
   ```html
   <link rel="stylesheet" href="../../shared/styles.css"/>
   ```
3. Add before `</body>`:
   ```html
   <script src="../../shared/auth.js"></script>
   ```
4. Initialise in your script:
   ```js
   ITTools.theme.init();
   ITTools.ui.renderTopbar({ toolName: "Your Tool Name" });

   await ITTools.auth.init({
     scopes: ["YourScope.Here"],
     onSignIn:  acct => { /* show app */ },
     onSignOut: ()   => { /* show auth screen */ }
   });
   ```
5. Use `ITTools.graph.get(url)`, `.getAll(url)`, `.post(url, body)` for all Graph calls — tokens are handled automatically.
6. Add the tool card to `index.html` and update the `README.md` table above.

## Tech stack

- Vanilla HTML/CSS/JS — no build step, no frameworks, no node_modules
- [MSAL Browser](https://github.com/AzureAD/microsoft-authentication-library-for-js) for authentication
- Microsoft Graph API for all M365 data
- GitHub Pages for hosting

## Author

Josh Garrett · [github.com/jgdev-ch](https://github.com/jgdev-ch)
