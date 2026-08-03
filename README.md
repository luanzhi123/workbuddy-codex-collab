# WorkBuddy × CodeX 协作规范仓库

把 WorkBuddy 在美菜小B风控工作中积累的经验、规范、偏好同步给 CodeX（OpenAI 云端编码助手），实现「WorkBuddy 守本地与业务域，CodeX 攻通用编码」的接力协作。

## 文件清单

| 文件 | 说明 |
|------|------|
| `CodeX_上下文包.md` | 主文档：协作定位、用户背景、SQL 高频规范、项目规则、输出偏好、Excel 规范、WorkBuddy skill 清单、协作约定、喂给 CodeX 的 3 种方式 |
| `LinkStar_SQL字典_CodeX版.md` | 完整 LinkStar/Doris 分区表规则 + 字段字典（已去除本地路径依赖，CodeX 直接可用） |
| `任务规格模板.md` | WorkBuddy → CodeX 的标准交接文件骨架（目标/脱敏样例/约束/验收），每次派活前复制填写 |

## 用法

1. 本仓库已 `git init` 并首次提交。等你建好空 GitHub 仓库后推远程：
   ```bash
   cd C:/Users/MC/WorkBuddy/协作
   git remote add origin <你的仓库URL>
   git branch -M main
   git push -u origin main
   ```
2. CodeX 开工前读取规范：
   ```bash
   cat CodeX_上下文包.md LinkStar_SQL字典_CodeX版.md
   ```
   或把 `CodeX_上下文包.md` 全文粘贴进 Codex 的 memory。
3. 派活给 CodeX 时，复制 `任务规格模板.md` 填写 0~6 节后交给它，作为标准交接契约。
3. WorkBuddy 这边更新规范后同步：
   ```bash
   git add -A && git commit -m "同步规范" && git push
   ```

## 维护约定

- 本地规范以 WorkBuddy 本机 `美菜-SQL代码/LinkStar_分区规则速查.md` 为准，更新后重新拷贝到本仓库的 `LinkStar_SQL字典_CodeX版.md`。
- 任何协作规则改动，两边都同步更新，保持单一事实源。
