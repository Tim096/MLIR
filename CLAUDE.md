# 給 Claude Code 的規則

本機與雲端 session 都適用。

- commit 的 author 與 committer 一律是 `Hung-Kuan Tseng <tseng.tim096@gmail.com>`。
- commit message、PR 內文、程式註解、文件都不放 Claude／Anthropic 的署名：
  不要 `Co-Authored-By`、`Assisted-by`、`Claude-Session`、`Generated with Claude Code`。
- `.githooks/` 會擋下違反以上兩條的 commit 與 push。被擋就照錯誤訊息修，不要用 `--no-verify` 繞過。
- 雲端 session 只能 push 到自己的分支。回報時寫出分支名，不要只寫「已 push」。
