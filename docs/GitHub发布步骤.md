# GitHub发布步骤

## 1. 发布前复核

确认仓库中不包含：

- 真实姓名或病历信息；
- FIF、SET、FDT、EDF等原始或预处理数据；
- markers.csv、结果MAT、PNG、XLSX；
- 本机绝对路径、账号、令牌或密码。

Windows PowerShell可执行：

```powershell
Get-ChildItem -Recurse -File
Get-ChildItem -Recurse -File | Select-String -Pattern 'C:\\Users|E:\\|真实姓名'
```

## 2. 在GitHub创建空仓库

在GitHub中新建仓库，例如：

```text
matlab-eeg-wpli-fsaverage
```

首次创建时不要勾选自动生成README、LICENSE或`.gitignore`，因为本地发布包已经包含这些文件。

建议先创建Private仓库进行一次网页端复核，确认后再改为Public。

## 3. 初始化本地Git仓库

在PowerShell进入发布包根目录：

```powershell
cd path\to\matlab-eeg-wpli-fsaverage
git init
git branch -M main
git add .
git status
```

仔细阅读`git status`。若出现数据文件或结果文件，立即停止，不要提交。

确认后提交：

```powershell
git commit -m "Initial public release"
```

## 4. 连接并推送GitHub

将下面地址替换成自己的仓库地址：

```powershell
git remote add origin https://github.com/YOUR_ACCOUNT/matlab-eeg-wpli-fsaverage.git
git push -u origin main
```

GitHub要求认证时，使用浏览器登录、Git Credential Manager或个人访问令牌。不要把令牌写入脚本或README。

## 5. 网页端再次检查

重点检查：

1. README中的目录、参数和解释边界是否正确；
2. 仓库搜索中是否出现真实姓名和本机盘符；
3. `src/`是否只有代码；
4. 是否意外上传数据、图片或结果表；
5. LICENSE和第三方软件说明是否存在。

## 6. 创建版本发布

当前发布版本为`0.1.3`。确认主分支后可以打标签：

```powershell
git tag -a v0.1.3 -m "Pilot release v0.1.3"
git push origin v0.1.3
```

然后在GitHub Releases中基于`v0.1.3`创建发布。发布说明应明确这是预实验流程，不是临床诊断软件。
