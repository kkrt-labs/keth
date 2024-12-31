# Cairo Addons

A collection of Cairo "addons", ie. cairo tools and libraries not part of the
Starkware core library.

## Installation

Any changes to the rust code requires a re-build and re-install of the python
package, see
[the uv docs](https://docs.astral.sh/uv/concepts/projects/init/#projects-with-extension-modules)
for more information.

The tl;dr is:

```bash
uv run --reinstall <command>
```

Forgetting the `--reinstall` flag will not re-build the python package and
consequentially not use any changes to the rust code.
