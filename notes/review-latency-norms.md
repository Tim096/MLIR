# 為什麼 20 個 open PR 只有 4 個有人回：規則與數據（2026-09-11）

一個唯讀 agent 查了 `llvm/docs`、抽樣 40 個 08-15～09-05 的 mlir PR、讀了四個已 approve PR 的全部留言、算了各 reviewer 的積壓。事實與推論分開寫。

## 白紙黑字的規則（`llvm/docs`）

| 規則 | 出處 | 原文 |
|---|---|---|
| 一週沒回才 ping，一週一次 | `Contributing.md` L119-122 | "If you have received no comments on your patch for a week, you can request a review by 'ping'ing the GitHub PR with "Ping" in a comment. The common courtesy 'ping' rate is once a week." |
| 週末假日不算 | `CodeReview.rst` L186-187 | "Please also be mindful of weekends and major holidays." |
| **approve 後要明講「請幫我 merge」** | `Contributing.md` L124-127 | "If you do not have the ability to merge the PR, ask your reviewers to merge it on your behalf. **You must do this explicitly, as reviewers' default assumption is that you are able to merge your own PR.**" |
| 代 commit 要給作者名與 email | `DeveloperPolicy.md` L489-492 | "please provide the name and email address you would like to use in the Author property" |
| 沒有同時幾個 PR 的上限 | — | 只有 `AIToolPolicy.md` L13-16 的 "start with small contributions ... taking small steps, getting feedback, and iterating" |
| AI 工具揭露 | `AIToolPolicy.md` L20-27、L40-42 | "label contributions that contain substantial amounts of tool-generated content ... note tool usage in their pull request description, commit message ... use a commit message trailer like Assisted-by"；"strongly recommended that contributors write PR descriptions themselves"。09-10 joker-eph 自己的 #219195 commit 就帶 `Assisted-by: Codex`。 |

## 基準數據（40 個別人的 mlir PR，08-15～09-05）

| | 全部 (40) | committer (28) | 非 committer (12) |
|---|---|---|---|
| 第一個人回覆：中位數（天） | 0.43 | 0.24 | **0.52** |
| merge：中位數（天） | 0.67 | 0.3 | **2.7** |
| 7 天沒人回 | 22% | 25%（全是自己 merge 的 NFC） | **17%**（12 個裡 2 個） |
| 完全沒人回 | 12% | 18% | **0%** |

非 committer 一週無人回的比例是六分之一。我 18 個 09-04／05 送的 PR 裡 13 個一週無人回，72%。這不是運氣。

## 四個已 approve 的 PR 實際發生了什麼

| PR | approve | 之後作者說了什麼 |
|---|---|---|
| #215696 | kuhar 08-14，附一句「想等第二個 approve，也許 krzysz00」 | 三則留言（08-16、08-21、09-04）都是「要不要繼續等？」的問句，沒有一句「請你 merge」 |
| #221248 | mplatings 09-04，開 PR 後 43 分鐘 | **零留言** |
| #221312 | krzysz00 09-05 | **零留言**，而且 09-10 #219195 之後跟 main 衝突（`mergeable_state: dirty`），committer 想按也按不下去 |
| #221314 | joker-eph 09-04、ioghiban 09-07 | 09-11 才第一次寫「I don't have commit access, could you land it」——**這是 20 個 PR 裡唯一一句明確的 merge 請求** |

## 13 個沒人回的 PR 長什麼樣

- ping 留言在開 PR 後 **1～137 秒**內貼出（#221386 1 秒、#221312 3 秒），全部集中在週五 09-04 15:11～18:52 UTC 與週六 09-05 03:15～03:53 UTC。
- 同一天點名同一個人：09-04 banach-space **9 次**、kuhar 5、dcaballe 5。
- 那兩天 mlir 總共開了 44 個 PR，我佔 18 個，**41%**。抽樣裡沒有任何非 committer 一天開超過 2 個。
- 被點名的人是最塞的人（open review request 數／近 14 天 review 數）：nicolasvasilache 184／0、dcaballe 155／3、kuhar 121／10、banach-space 110／24。有量能又會回的：krzysz00 76／**78**、joker-eph 111／**55**、FedericoBruzzone 2／**30**、matthias-springer 118／20。krzysz00 與 joker-eph 被點名的那幾個都在幾小時內回了。

## 別人怎麼寫（非 committer，7～9 月）

- #215331 tridhapuku：「Thanks for the review, @matthias-springer ! I don't have commit access — could you merge this when you have a moment?」approve 後 1 小時貼，4 天 merge。
- #216799 hamzaqureshi5：「Could you land this for me? I don't have commit access.」隔天 merge。
- #216851 alepot55：「I do not have commit access, so could one of you land this when you get a chance? Author: `Alessandro Potenza <...>`.」隔天 merge。
- #214552 jaredhoberock：「Rebased onto main, everything looks green. I don't have commit access, could you land this when convenient?」隔天 merge。
- #217511 amanyagami（16 天沒人理）：「Ping — this has had no reviewer since it was opened 16 days ago ... @matthias-springer @FedericoBruzzone you have been the most active reviewers on `mlir:affine` lately — would one of you be able to take a look, or redirect me to someone better placed?」2.5 小時後 approve。
- 反例 #216854 alepot55：週末兩天內催兩次，FedericoBruzzone 回「this community is global in nature, so sometimes it's necessary to be a little patient. Note that the weekend is excluded from any hypothetical count.」

18 個 merge 請求裡 16 個是同一個模板：`Thanks @X` ＋ `I don't have commit access` ＋ `could you land/merge when convenient`，1～3 句，approve 當天貼，通常一天內 merge。

## 推論（與上面的事實分開）

1. **漏掉的規則是 `Contributing.md` L126**：approve 不會自動變 merge，要明講。#221248、#221312 完全沒講；#215696 講的是問句；#221314 今天才講。#221312 還多一個衝突。
2. **量與時間點不尋常**：13 小時內 18 個 PR，週五晚到週六 UTC，每個都在建立後幾秒點名同三個人。文件的「小步、拿回饋、再迭代」與「一週再 ping」都指向相反方向。
3. **點錯人**：dcaballe、nicolasvasilache 實質上不在線；有量能的 FedericoBruzzone、krzysz00、joker-eph 只被點了 1～3 次，而且他們都回了。
4. **AI policy 已經被問過一次**（#221268，FedericoBruzzone 09-05）。一個晚上看到 13 個標題同款的「Keep X attributes」PR 的 reviewer 可能默默套用同一個濾鏡。

## 09-11 據此做的事

- #221248、#215696：補上明確的 merge 請求（#215696 同時點 krzysz00 給第二個 approve）。
- #221312：rebase 到 main（#219195 改了 builder call site），CI 綠後請 krzysz00 merge。
- 09-04 那批滿一週的六個：一行 ping，改點有量能的人（#221185 → joker-eph，該檔案前兩個 bug 是他修的；#221307 → FedericoBruzzone，他 review 過同款的 #216947；#221308 → krzysz00，附「#221312 的 AMDGPU 版」這個新資訊；#221288 → fabianmcg／grypp；#221298 → raikonenfnu／banach-space）。banach-space 今天只點一次。
- 09-05 那批七個（#221317、#221319、#221320、#221382、#221383、#221385、#221386）：09-12 才滿一週，且中間隔週末，**下週一（09-14）以後**再 ping，分散到不同的人。
- #221293 與 09-05 landed 的 #219192 撞：另見 [`insert-slice-vectorize-precondition.md`](insert-slice-vectorize-precondition.md)。

## 以後的作法

- approve 當天就貼模板句，附 Author 名與 email。
- 一天最多 2～3 個 PR（[[upstream-pr-description-norms]] 早就這樣寫），週五下午以後不送。
- ping 前先看 reviewer 近 14 天有沒有在 review：`gh api "search/issues?q=repo:llvm/llvm-project+is:pr+reviewed-by:<login>+updated:>YYYY-MM-DD"`。
- 送 PR 時不要在建立後幾秒內 ping；CODEOWNERS 自動指派的人一週沒回再點名，點名時說為什麼是他（他修過這個檔、他 review 過同款）。
