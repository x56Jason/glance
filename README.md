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

### 'Glance log' Command

Open Glance log view by the 'Glance log' command:

```vim
:Glance log
```

### 'Glance patchdiff' Command

You can also use 'patchdiff' sub-command to set the display mode for the diff between upstream and backport commit.

If the mode is "diffonly", the diff of commit message will not show.

By default the display mode is "diffonly".

```vim
:Glance patchdiff [full|diffonly]
```

### 'Glance q_quit_log' Command

You can also use 'q_quit_log' sub-command to enable pressing 'q' to quit log view when in it.

By default, it is off

```vim
:Glance q_quit_log [on|off]
```

### Keymaps

In Glance log view, on each commit, following keymaps are available:

| Key     | Description                                               |
|---------|-----------------------------------------------------------|
| <enter> | show the current commit                                   |
|    p    | show the diff between upstream commit and backport commit |
|    l    | show side by side the upstream commit and backport commit |
|    q    | close the corresponding window                            |

