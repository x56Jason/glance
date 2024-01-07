if exists("b:current_syntax")
  finish
endif

syn match GlancePatchDiffAdd /.*/ contained
syn match GlancePatchDiffDelete /.*/ contained

hi def GlancePatchDiffAdd guibg=#000000 guifg=#859900
hi def GlancePatchDiffDelete guibg=#000000 guifg=#dc322f
hi def GlancePatchDiffHunkHeader guifg=#cccccc guibg=#404040
hi def GlancePatchDiffFilePath guifg=#798bf2

hi def GlancePatchDiffViewHeader guifg=#ffffff guibg=#94bbd1

hi def PRDiffAdd guifg=#ffffff guibg=#008000
hi def PRDiffDel guifg=#ffffff guibg=#ff0000

sign define GlancePatchDiffHunkHeader linehl=GlancePatchDiffHunkHeader

sign define GlancePatchDiffAdd linehl=GlancePatchDiffAdd
sign define GlancePatchDiffDelete linehl=GlancePatchDiffDelete

sign define GlancePatchDiffViewHeader linehl=GlancePatchDiffViewHeader
sign define GlancePatchDiffViewDescription linehl=GlancePatchDiffHunkHeader
