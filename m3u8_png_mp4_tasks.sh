#!/bin/bash

# 对于那些网站是m3u8却返回png的，可以尝试使用这个脚本下载
# 仅限于简单的的png->ts文件转换（去处png文件开头的212个字节），暂不支持加密文件的转换

DOWNLOAD_DIR="downloads"
TS_DIR="ts"
MAX_JOB_COUNT=35
MAX_ATTEMPTS=5

# 检查是否安装了 yq （用于解析JSON）
if ! command -v yq &> /dev/null; then
    echo "yq 未安装，正在安装..."
    # 在 Ubuntu 上安装 yq
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y yq
    # 在 macOS 上安装 yq
    elif command -v brew &> /dev/null; then
        brew install yq
    # 在 Windows 上安装 yq
    elif command -v choco &> /dev/null; then
        choco install yq
    else
        echo "无法自动安装 yq，请手动安装。"
        exit 1
    fi
fi

# 初始化存储空间
init_workspace() {
    mkdir -p "$workspace"
    echo "存储空间设置为:$workspace"
}

# 初始化下载文件目录
init_tmp_workspace(){
    tmp_workspace="$workspace/$output_file"
    #清除tmp_workspace如果已经存在了
    rm -rf "$tmp_workspace"
    mkdir -p "$tmp_workspace"
    echo "已创建临时下载任务目录: $tmp_workspace" >> "$tmp_workspace/log.txt"
}

# 清理文件函数
cleanup_files() {
  echo "正在清理文件..."
  rm -rf "$tmp_workspace"
}

# 中止进程
cleanup_subprocesses() {
  echo "正在清理所有子进程..."
  # 使用jobs -p获取所有子进程的PID，然后用kill命令结束它们
  kill $(jobs -p) 2>/dev/null
}

exit_and_cleanup() {
    cleanup_subprocesses
    cleanup_files
    echo "正在退出脚本..."
    exit
}

# 主要下载逻辑
download() {
  base_url=$(echo $m3u8_url | sed -E 's|(https?://[^/]+).*|\1|')

  # 下载M3U8文件
  mkdir -p "$tmp_workspace/$DOWNLOAD_DIR"
  m3u8_file="$tmp_workspace/$DOWNLOAD_DIR/playlist.m3u8"
  curl "$m3u8_url" -o "$m3u8_file"

  # 下载和转换PNG文件
  mkdir -p "$tmp_workspace/$TS_DIR"
  png_urls=$(grep -E '^[^#].*[^[:space:]]' "$tmp_workspace/$DOWNLOAD_DIR/playlist.m3u8")

  echo "发现: $(echo "$png_urls" | wc -l) 个资源文件需要下载" >> "$tmp_workspace/log.txt"

  for url in $png_urls; do
    if [[ ! "$url" =~ ^http ]]; then
      url="${base_url}${url}"
    fi
    
    filename=$(basename "$url")
    png_file="$tmp_workspace/$DOWNLOAD_DIR/$filename"
    ts_file="$tmp_workspace/$TS_DIR/${filename}.ts"

    while [ $(jobs -p | wc -l) -ge $MAX_JOB_COUNT ]; do
      # echo "已达到最大后台进程数，休眠1秒后重试" >> "$tmp_workspace/log.txt"
      sleep 1
    done
    
    (
      attempts=0
      while [ $attempts -lt $MAX_ATTEMPTS ]; do
        if curl -L "$url" -o "$png_file" && [ -s "$png_file" ]; then
            echo "下载 $url 成功" >> "$tmp_workspace/log.txt"
            echo "正在转换 $filename 到ts文件..." >> "$tmp_workspace/log.txt"
            dd if="$png_file" of="$ts_file" bs=4 skip=53
            # 验证是否是ts文件，有时候可能是被封了，返回的是html文件或是其他格式的文件
            if ffprobe -v error -show_format -i "$ts_file" 2>&1 | grep -q "format_name=mpegts"; then
              echo "转换文件 $filename 成功" >> "$tmp_workspace/log.txt"
              break
            fi
            echo "转换ts文件失败，可能不是ts文件，详情去ts目录下查看 $ts_file 是否存在以及它的内容" >> "$tmp_workspace/log.txt"
        fi
        echo "第 $((attempts+1)) 次尝试下载或转换失败，5秒后重试" >> "$tmp_workspace/log.txt"
        sleep 5
        attempts=$((attempts+1))
      done
      if [ $attempts -eq $MAX_ATTEMPTS ]; then
          echo "下载资源 $workspace/$output_file.mp4 失败，资源链接:$url" >> "$workspace/failed_downloads.txt"
      fi
    )&
  done

  # 等待所有后台任务完成
  wait

  # 先把原始的m3u8文件复制一份到ts目录下
  cp "$tmp_workspace/$DOWNLOAD_DIR/playlist.m3u8" "$tmp_workspace/$TS_DIR/playlist.m3u8"
  # 替换URL为本地文件名
  for url in $png_urls; do
    filename=$(basename "$url").ts
    awk -v old="$url" -v new="$filename" '{gsub(old, new); print}' "$tmp_workspace/$TS_DIR/playlist.m3u8" > tmp.m3u8 && mv tmp.m3u8 "$tmp_workspace/$TS_DIR/playlist.m3u8"
  done

  # 如果存在failed_downloads.txt文件，则说明有下载失败的资源
  if [ -f "$workspace/failed_downloads.txt" ]; then
    echo "$workspace/$output_file.mp4存在下载失败的资源，不进行视频合并" >> "$tmp_workspace/log.txt"
    echo "视频下载失败，去 "$tmp_workspace/log.txt" 查看详情"
    return
  fi

  echo "已下载和转换所有ts文件，正在合并文件..." >> "$tmp_workspace/log.txt"

  if ffmpeg -i "$tmp_workspace/$TS_DIR/playlist.m3u8" -c copy "$workspace/$output_file.mp4" >> "$tmp_workspace/log.txt" 2>&1; then
    echo "视频下载成功！文件保存在 "$workspace/$output_file.mp4""
    cleanup_files
  else
    echo "视频合并失败" >> "$tmp_workspace/log.txt"
    echo "视频下载失败，去 "$tmp_workspace/log.txt" 查看详情"
  fi
}


# 设置信号处理
trap exit_and_cleanup SIGINT SIGTERM

# 默认的任务文件名
task_file="tasks.yml"

init_tasks() {
  # 如果文件不存在，则退出 
  if [ ! -f "$task_file" ]; then
    echo "任务文件不存在: $task_file"
    exit 1
  fi
  echo "找到任务文件: $task_file"
  # 读取任务文件
  workspaces=$(yq '.tasks[].workspace.path' $task_file)
  i=0
  for workspace in $workspaces; do
    echo "正在处理存储空间: $workspace"
    # 移除注释，然后根据索引把当前存储空间中的下载任务的信息放入entry数组
    tasks=$(yq '... comments="" | .tasks['"$i"'].workspace' $task_file)
    echo "$tasks" | while IFS= read -r line; do
        output_file=$(echo "$line" | cut -d ':' -f 1)
        m3u8_url=$(echo "$line" | cut -d ':' -f 2-)
        # 跳过path键
        if [ "$output_file" == "path" ]; then
            continue
        fi
        # 开始下载任务
        echo "正在处理下载任务: $output_file"
        init_workspace
        init_tmp_workspace
        download
    done
    i=$((i+1))
  done
}

# 解析命令行参数
while getopts "t:" opt; do
  case $opt in
    t)
      task_file="$OPTARG"
      ;;
    \?)
      # 提示正确的用法
        echo "命令中存在无效参数，正确用法:"
        echo "m3u8_png_mp4_tasks.sh [-t task_file]"
      ;;
  esac
done

init_tasks
