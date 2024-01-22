if exists("b:current_syntax")
  finish
endif

"syn match Function /^[a-z0-9]\{12}\ze/

"hi def GlanceLogCommit guibg=#000000 guifg=#94bbd1
hi def GlanceLogCommit guibg=#000000 guifg=#859900
hi def GlanceLogRemote guibg=#000000 guifg=#dc322f
hi def GlanceLogSubject guibg=#000000 
hi def GlanceLogHeader guibg=#000000 guifg=#94bbd1
hi def GlanceLogHeaderField guifg=#dca561 guibg=#000000
"hi def GlanceLogHeaderHead guibg=#000000 guifg=#e82424
hi def GlanceLogHeaderHead guibg=#000000 guifg=#dc322f
hi def GlanceLogHeaderBase guibg=#000000 guifg=#008000
hi def GlanceLogCLAYes guibg=#000000 guifg=#20c22e
hi def GlanceLogLGTM guibg=#000000 guifg=#20c22e
hi def GlanceLogCISuccess guibg=#000000 guifg=#20c22e
hi def GlanceLogSigKernel guibg=#000000 guifg=#1dcaf9
hi def GlanceLogNeedSquash guibg=#000000 guifg=#febc08
hi def GlanceLogNewComer guibg=#000000 guifg=#1083d6
hi def GlanceLogCommentHead guibg=#000000 guifg=#94bbd1
hi def GlanceLogCompareList guibg=#000000 guifg=#20c22c

sign define GlanceLogHeader linehl=GlanceLogHeader
sign define GlanceLogHeaderField linehl=GlanceLogHeaderField
sign define GlanceLogHeaderHead linehl=GlanceLogHeaderHead
sign define GlanceLogHeaderBase linehl=GlanceLogHeaderBase
sign define GlanceLogCommentHead linehl=GlanceLogCommentHead

