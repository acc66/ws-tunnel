#!/bin/bash
# 推送到 GitHub 脚本

echo "================================================"
echo "  推送 WebSocket Tunnel 到 GitHub"
echo "================================================"
echo ""

# 检查是否已经有远程仓库
if git remote | grep -q "origin"; then
    echo "检测到已有 origin 远程仓库"
    git remote -v
    echo ""
    read -p "是否要删除现有 origin 并重新设置? [y/N]: " RESET
    if [[ "$RESET" =~ ^[Yy]$ ]]; then
        git remote remove origin
    else
        echo "保持现有 origin"
    fi
fi

# 如果没有 origin，询问 GitHub 仓库地址
if ! git remote | grep -q "origin"; then
    echo ""
    echo "请先在 GitHub 创建一个新仓库，然后输入仓库地址"
    echo "格式示例："
    echo "  HTTPS: https://github.com/yourusername/ws-tunnel.git"
    echo "  SSH:   git@github.com:yourusername/ws-tunnel.git"
    echo ""
    read -p "输入 GitHub 仓库地址: " REPO_URL

    if [ -z "$REPO_URL" ]; then
        echo "❌ 错误: 仓库地址不能为空"
        exit 1
    fi

    echo ""
    echo "添加远程仓库..."
    git remote add origin "$REPO_URL"
fi

echo ""
echo "当前远程仓库:"
git remote -v
echo ""

# 确认推送
read -p "确认推送到 GitHub? [Y/n]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Nn]$ ]]; then
    echo ""
    echo "🚀 推送到 GitHub..."

    # 推送主分支
    git push -u origin master || git push -u origin main

    echo ""
    echo "✅ 推送完成！"
    echo ""
    echo "================================================"
    echo "  后续步骤"
    echo "================================================"
    echo ""
    echo "1. 访问你的 GitHub 仓库"
    echo "2. 创建一个 Release 标签来触发自动编译："
    echo ""
    echo "   git tag v1.0.0"
    echo "   git push origin v1.0.0"
    echo ""
    echo "3. GitHub Actions 会自动编译所有平台的版本"
    echo "4. 编译完成后会自动创建 Release 并上传文件"
    echo ""
    echo "或者手动在 GitHub 网页上创建 Release:"
    echo "  - 进入仓库 → Releases → Create a new release"
    echo "  - 创建新标签: v1.0.0"
    echo "  - 发布后 GitHub Actions 会自动编译"
    echo ""
else
    echo "取消推送"
fi
