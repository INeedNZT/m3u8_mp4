#!/bin/bash

# 对于那些网站是m3u8却返回png的，可以尝试使用这个脚本下载
# 仅限于简单的的png->ts文件转换（去处png文件开头的212个字节），暂不支持加密文件的转换

DOWNLOAD_DIR="downloads"
TS_DIR="ts"
MAX_JOB_COUNT=35
MAX_ATTEMPTS=5

# 初始化存储空间
init_workspace() {
    echo "请输入存储空间的路径（将在此目录下保存所有文件）:"
    read workspace
    mkdir -p "$workspace"
    echo "存储空间设置为:$workspace"
}

# 初始化下载文件目录
init_tmp_workspace(){
    tmp_workspace="$workspace/$output_file"
    # 输出文件名的文件夹
    mkdir -p "$tmp_workspace"
    echo "已创建临时下载任务目录: $(pwd "$tmp_workspace")" >> "$tmp_workspace/log.txt"
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
  # 清理旧文件
  cleanup_files

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
          echo "$url" >> failed_downloads.txt
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

  echo "已下载和转换所有ts文件，正在合并文件..." >> "$tmp_workspace/log.txt"

  if ffmpeg -i "$tmp_workspace/$TS_DIR/playlist.m3u8" -c copy "$workspace/$output_file.mp4" >> "$tmp_workspace/log.txt" 2>&1; then
    echo "视频下载成功！文件保存在 $(pwd "$tmp_workspace/$output_file.mp4")"
    cleanup_files
  else
    echo "视频合并失败" >> "$tmp_workspace/log.txt"
    echo "视频下载失败"，去 $(pwd "$tmp_workspace/log.txt") 查看详情"
  fi
}

# 初始化存储空间
init_workspace

# 设置信号处理
trap exit_and_cleanup SIGINT SIGTERM

while true; do
  # 用户交互，选择操作
  echo "请选择操作:"
  echo "1. 创建下载任务"
  echo "2. 退出"
  read -p "请输入选项（1/2）:" option
  # 根据用户选择执行相应操作
  case $option in
    1)
      read -p "请输入M3U8 URL:" m3u8_url
      read -p "请输入输出文件名（不需要mp4后缀）:" output_file
      init_tmp_workspace 
      download
      ;;
    2)
      exit_and_cleanup
      ;;
    *)
      echo "无效选项，程序退出"
      ;;
  esac
done
