# Cover sources

Each `cover-*.html` here is the source for the matching PNG in `covers/`. They are
1200x630 artboards on the series template: dark navy, the `// The Workbench` brand
line, a kicker, a big title, a subtitle, and a small diagram that tells the article's
story in two panels.

## Building a cover

1. Copy the closest existing source and rename it for the new post.
2. Swap the kicker, title, subtitle, and diagram nodes.
3. Render:
   `msedge --headless=new --screenshot=covers/cover-NN-slug.png --window-size=1200,630 --virtual-time-budget=8000 "file:///.../covers/src/cover-NN-slug.html"`
4. Commit the HTML and the PNG together, one commit per cover change, message
   naming the post.

The blog hotlinks the PNGs from this repo (raw.githubusercontent.com), so a pushed
change to a PNG is live on the blog immediately. Branch protection blocks force
pushes and deletions; history is linear.
