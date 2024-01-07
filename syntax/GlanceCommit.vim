if exists("b:current_syntax")
  finish
endif

syn match GlanceCommitDiffAdd /.*/ contained
syn match GlanceCommitDiffDelete /.*/ contained

hi def GlanceCommitDiffAdd guifg=#000000 guibg=#859900
hi def GlanceCommitDiffDelete guifg=#ffffff guibg=#dc322f
hi def GlanceCommitHunkHeader guifg=#cccccc guibg=#404040
hi def GlanceCommitFilePath guifg=#798bf2

hi def GlanceCommitViewHeader guifg=#000000 guibg=#94bbd1

sign define GlanceCommitHunkHeader linehl=GlanceCommitHunkHeader

sign define GlanceCommitDiffAdd linehl=GlanceCommitDiffAdd
sign define GlanceCommitDiffDelete linehl=GlanceCommitDiffDelete

sign define GlanceCommitViewHeader linehl=GlanceCommitViewHeader
sign define GlanceCommitViewDescription linehl=GlanceCommitHunkHeader
