#!/bin/bash

# 初始化存储空间
init_workspace() {
    echo "请输入存储空间的路径（将在此目录下保存所有文件）:"
    read workspace
    mkdir -p "$workspace"
    pid_file="$workspace/download_pids.txt"
    temp_file="$workspace/temp_pids.txt"
    touch "$pid_file"
    echo "存储空间设置为：$workspace"
}

# 函数：创建后台下载任务
download() {
    echo "请输入M3U8 URL:"
    read m3u8_url

    echo "请输入输出文件名:"
    read output_file

    output_path="$workspace/$output_file.mp4"

    # 使用ffmpeg创建后台下载任务，并记录PID和文件名
    nohup ffmpeg -http_seekable 0 -i "$m3u8_url" -c:v copy -c:a aac -strict experimental "$output_path" > /dev/null 2>&1 &
    # nohup ffmpeg -http_seekable 0 -i "$m3u8_url" -c:v libx264 -c:a aac -strict experimental "$output_path" > /dev/null 2>&1 &
    echo "$! $output_file" >> "$pid_file"
    echo "后台下载任务创建成功，输出文件名为：$output_file ，保存在存储空间内"
}

# 函数：查询当前运行的后台下载任务，并清理已结束的任务信息
query() {
    echo "正在运行的后台下载任务："
    > "$temp_file"  # 清空临时文件
    while read pid name; do
        if ps -p $pid > /dev/null; then
           echo "$pid: $name"
           echo "$pid $name" >> "$temp_file"
        fi
    done < "$pid_file"

    # 检查临时文件是否存在，如果存在则用其替换原文件
    if [ -s "$temp_file" ]; then
        mv "$temp_file" "$pid_file"
    else
        > "$pid_file"  # 清空原文件，因为没有运行中的任务
    fi
}

# 清理并退出
cleanup_and_exit() {
    echo "正在清理..."
    rm -f "$pid_file" "$temp_file"  # 删除文件
    echo "退出脚本。"
    exit 0
}

# 主菜单
init_workspace
trap cleanup_and_exit EXIT  # 注册退出时的清理函数

while true; do
    echo "请选择操作："
    echo "1) 创建后台下载任务"
    echo "2) 查询正在运行的后台下载任务"
    echo "3) 退出"
    read -p "输入选项（1/2/3）: " option

    case $option in
        1)
            download
            ;;
        2)
            query
            ;;
        3)
            exit 0
            ;;
        *)
            echo "无效选项，请重新输入。"
            ;;
    esac
done
