# Introduction

Glance is a simple plugin for [Neovim](https://neovim.io) to speed up backporting code review.

It is based on some early version of [NeoGit](https://github.com/NeogitOrg/neogit).

## Installation & Configuration

If you are using [Lazy](https://github.com/folke/lazy.nvim) plugin manager, just use following spec:

```lua
{
    "x48Jason/glance",
    config = true,
}
```

If you are not using Lazy, make sure the plugin is initialized like:

```lua
-- init.lua
local glance = require("glance")
glance.setup{}
```

## Usage

### 'Glance' Command

Open Glance log view by the 'Glance' command:

```vim
:Glance
```

### 'Patchdiff' Command

You can also use 'Patchdiff' command to set the display mode for the diff between upstream and backport commit.

If the mode is "diffonly", the diff of commit message will not show.

By default the display mode is "diffonly".

```vim
:Patchdiff [full|diffonly]
```

### Keymaps

In Glance log view, on each commit, following keymaps are available:

| Key     | Description                                               |
|---------|-----------------------------------------------------------|
| <enter> | show the current commit                                   |
|    p    | show the diff between upstream commit and backport commit |
|    l    | show side by side the upstream commit and backport commit |
|    q    | quit the 'p' or 'l' or '<enter>' window                   |

