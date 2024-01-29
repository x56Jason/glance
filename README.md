# Introduction

Glance is a plugin for [Neovim](https://neovim.io) to speed up backporting code review, especially for Gitee.com pull-request workflow.

It is based on some early version of [NeoGit](https://github.com/NeogitOrg/neogit).

# Dependencies

- The ['plenary.nvim'](https://github.com/nvim-lua/plenary.nvim) plugin is a dependency.

- The ['telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) plugin is also a dependency if you want to refine or filter in PRList view.

# Installation & Configuration

If you are using [Lazy](https://github.com/folke/lazy.nvim) plugin manager, the following spec can be used.

For Gitee usage, you need to generate a private token for Gitee API usage. 

You can omit the gitee part if you are not using for Gitee pull-request workflow.

```lua
{
    "x48Jason/glance",
    opts = {
        gitee = {
            token_file = "~/.token.gitee",
            repo = "openeuler/kernel",
            prlist_state = "open",
            prlist_sort = "updated",
        },
        patchdiff = "diffonly",
        q_quit_log = "off",
    }
}
```

If you are not using Lazy, make sure the plugin is initialized like:

```lua
-- init.lua
local glance = require("glance")
local opts = {
    gitee = {
        token_file = "~/.token.gitee",
        repo = "openeuler/kernel",
    },
    patchdiff = "diffonly",
    q_quit_log = "off",
}
glance.setup(opts)
```

# Usage

## 'Gitee prlist' Command

```vim
:Gitee prlist [state=<pr-state>] [sort=<sort-type>] [num]
```

This command is to retrieve pull-request list from gitee. The pull-request list will be displayed in a new window (PRList view).

It can have following parameters:

- [num]: denotes the number of pull-requests to be retrieved from gitee.com.
- [state=\<pr-state\>]: what state the retrieved pull-requests should be in. It can be one of the following:
    - open: the still open pull-request
    - closed: the closed pull-requests
    - merged: already merged pull-requests.
    - all: all pull-requests
- [sort=\<sort-type\>]: what sort strategy when retrieve pull-requests. It can be one of the following:
    - created: sort by create time
    - updated: sort by update time
    - popularity: sort by popularity
    - long-running: sort by long-running

In PRList view, the following keymap is available:

- Press \<enter\> on one pull-requests will fetch the details of this pull-requests from gitee.com and show it in a window.

- Press \<F5\> to refresh the pull-requests

- Press \<c-g\> to bring up telescope window to filter pull-requests.

In telescope window, you can use fzf filtering mechanisms to filter the pull-requests. Meanwhile, following keys are available:

- Press \<Tab\> to select a pull-request
- Press \<c-a\> to select all pull-request
- Press \<c-g\> to bring up a new PRList view for the selected pull-requests
- Press \<c-z\> to further fuzzy-refine the filtering result
- Press \<c-l\> to scroll-right the result window
- Press \<c-h\> to scroll-left the result window
- Press \<F5\> to refresh the pr list.
- Press \<enter\> to bring up the PR logview.

See following command for how to operate on a pull-request.

## 'Gitee pr' Command

```vim
:Gitee pr [pr-num]
```

Retrieve detailed information for a pull-request numbered [num] from gitee.com and show it in a window.

The window is devided into 3 parts:
- The top part is the Header part, where the meta data of the pull-requests will be shown.
- The middle part is the Commits part, where all the commits of this pull-requests will be shown.
- The bottom part is the Comments part, where all the comments for this pull-requests will be shown

### Browse Commit Patch

The following keys are available for showing patches in different ways.

- Press \<enter\> on one commit will show the patch of this commit.
- Press 'l' on one commit will show the upstream commit patch and the backport commit patch, if it is a backport commmit.
- Press 'p' on one commit will show the diff between upstream commit patch and the backport commit patch, if it is a backport commit. Aka, diff of patch.
- Press \<F5\> to refresh the pr log vie.
- Press 'q' on the diff window will quit the diff window.

In 'l' and 'p' command, glance will try to find the upstream commit id from the "commit xxxxxx" line in the commit message.

### Checkout Commit into Workspace

When in commit-patch (\<enter\> pressed on a commit), \<Ctrl-o\> will checkout the commit into current workspace, and start editing the file corresponding to current diff hunk.

### Add Comment for Pull-Request

Use \<Ctrl-r\> to add a comment for current pull-request.

### Delete Comment for Pull-Request

When cursor is in the area of a comment for the pull-request, \<ctrl-d\> will delete the comment.

## 'Glance log' Command

This is for non-Gitee mode. If you fetched changes to local repo, you can directly use this command to browse the commits.

```vim
:Glance log
```
This will read as much as 256 commits from the repo.

If you want to customize the commits that will be read-in, you can append any git-log arguments to 'Glance log', such as:

```vim
:Glance log v6.6..HEAD
```

## CompareList

Sometimes there is no "commit xxxxxxx" line in the commit message, but it does be backported from some commit on other branch.

In order to compare, you can use 'Glance log' command to list commits on other branch, and:
- Use \<ctrl-a\> to add a commit into the CompareList
- Use visual mode selection, such as 'V' to select commit range, and then use \<ctrl-s\> to add these commits to CompareList in batch.

After adding commits to CompareList, when use 'l' and 'p' commands in LogView or Gitee PR Logview, glance will try to find the commit in CompareList with the same title to do the diff.

## 'Glance patchdiff' Command

You can also use 'patchdiff' sub-command to set the display mode for the diff between upstream and backport commit.

If the mode is "diffonly", the diff of commit message will not show.

By default the display mode is "diffonly".

```vim
:Glance patchdiff [full|diffonly]
```

## 'Glance q_quit_log' Command

You can also use 'q_quit_log' sub-command to enable pressing 'q' to quit log view when in it.

By default, it is off

```vim
:Glance q_quit_log [on|off]
```
