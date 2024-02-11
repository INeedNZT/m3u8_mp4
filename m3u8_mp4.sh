#!/bin/bash

# 初始化存储空间
init_workspace() {
    echo "请输入存储空间的路径（将在此目录下保存所有文件）:"
    read workspace
    mkdir -p "$workspace"
    echo "存储空间设置为：$workspace"
}

cleanup_files() {
  rm -f "$workspace"/log.txt
  echo "清理完成!"
}

exit_and_cleanup() {
    cleanup_files
    echo "正在退出脚本..."
    exit
}

# 函数：创建后台下载任务
download() {
    echo "请输入M3U8 URL:"
    read m3u8_url

    echo "请输入输出文件名（不需要后缀）:"
    read output_file

    output_path="$workspace/$output_file.mp4"

    echo "下载任务创建成功，输出文件名为：$output_file.mp4 ，保存在存储空间内"
    echo "开始下载，请稍后..."
    # 使用ffmpeg创建后台下载任务，将输出重定向到日志文件log.txt
    ffmpeg -http_seekable 0 -i "$m3u8_url" -c:v copy -c:a aac -strict experimental "$output_path" >> "$workspace/log.txt" 2>&1
    # 碰到有些网站的资源可能转码会好一点，不过会很慢
    # ffmpeg -http_seekable 0 -i "$m3u8_url" -c:v libx264 -c:a aac -strict experimental "$output_path" >> "$workspace/log.txt" 2>&1
    if [ $? -eq 0 ]; then
        echo "视频下载成功！文件保存在 $output_path"
    else
        echo "视频下载失败，去 $workspace/log.txt 查看详情"
    fi
}

# 主菜单
init_workspace

# 设置信号处理
trap exit_and_cleanup SIGINT SIGTERM

while true; do
    echo "请选择操作："
    echo "1) 创建下载任务"
    echo "2) 退出"
    read -p "输入选项（1/2）: " option

    case $option in
        1)
            download
            ;;
        2)
            exit_and_cleanup
            ;;
        *)
            echo "无效选项，请重新输入。"
            ;;
    esac
done
