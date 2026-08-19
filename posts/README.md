# Post sources

Working copies of published Blogger articles that have been brought down for
update or review. The rule, standing since 2026-08-19:

1. **Pull first, commit immediately.** Before any edit, fetch the CURRENT live
   content from the Blogger API and commit it as
   "Pull from Blogger: <title> (as live <date>)". That commit is the baseline.
2. **One commit per change**, message naming the change, BEFORE it is patched
   back to Blogger. The repo never lags what is live.
3. Files follow the permalink: `posts/<yyyy>/<mm>/<slug>.html`.
4. Blogger remains the publishing surface; this folder is the change history.
   `git log --follow` on a file shows every edit an article underwent.
