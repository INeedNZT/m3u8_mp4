#!/bin/bash

# 对于那些网站是m3u8却返回png的，可以尝试使用这个脚本下载
# 仅限于简单的的png->ts文件转换（去处png文件开头的212个字节），暂不支持加密文件的转换

DOWNLOAD_DIR="downloads"
TS_DIR="ts"
MAX_JOB_COUNT=35
MAX_ATTEMPTS=5

# 清理文件函数
cleanup_files() {
  echo "正在清理文件..."
  rm -rf "$DOWNLOAD_DIR"
  rm -rf "$TS_DIR"
  rm -f failed_downloads.txt
  rm -f log.txt
}

# 中止进程
cleanup_subprocesses() {
  echo "正在清理所有子进程..."
  # 使用jobs -p获取所有子进程的PID，然后用kill命令结束它们
  kill $(jobs -p) 2>/dev/null
}

# 设置信号处理
trap cleanup_subprocesses SIGINT SIGTERM

# 主要下载逻辑
download() {
  M3U8_URL=$1  # M3U8链接
  FINAL_VIDEO=$2  # 输出视频文件名
  base_url=$(echo $M3U8_URL | sed -E 's|(https?://[^/]+).*|\1|')
  # 清理旧文件
  cleanup_files

  # 下载M3U8文件
  mkdir -p "$DOWNLOAD_DIR"
  m3u8_file="$DOWNLOAD_DIR/playlist.m3u8"
  curl "$M3U8_URL" -o "$m3u8_file"

  # 下载和转换PNG文件
  mkdir -p "$TS_DIR"
  png_urls=$(grep -E '^[^#].*[^[:space:]]' "$DOWNLOAD_DIR/playlist.m3u8")

  echo "发现: $(echo "$png_urls" | wc -l) 个资源文件需要下载" >> log.txt

  for url in $png_urls; do
    if [[ ! "$url" =~ ^http ]]; then
      url="${base_url}${url}"
    fi
    
    filename=$(basename "$url")
    png_file="$DOWNLOAD_DIR/$filename"
    ts_file="$TS_DIR/${filename}.ts"

    while [ $(jobs -p | wc -l) -ge $MAX_JOB_COUNT ]; do
      # echo "已达到最大后台进程数，休眠1秒后重试" >> log.txt
      sleep 1
    done
    
    (
      attempts=0
      while [ $attempts -lt $MAX_ATTEMPTS ]; do
        if curl -L "$url" -o "$png_file" && [ -s "$png_file" ]; then
            echo "下载 $url 成功" >> log.txt
            echo "正在转换 $filename 到ts文件..." >> log.txt
            dd if="$png_file" of="$ts_file" bs=4 skip=53
            if ffprobe -v error -show_format -i "$ts_file" 2>&1 | grep -q "format_name=mpegts"; then
              echo "转换文件 $filename 成功" >> log.txt
              break
            fi
            echo "转换ts文件失败，可能不是ts文件，详情去ts目录下查看 $ts_file 是否存在以及它的内容" >> log.txt
        fi
        echo "第 $((attempts+1)) 次尝试下载或转换失败，5秒后重试" >> log.txt
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
  cp "$DOWNLOAD_DIR/playlist.m3u8" "$TS_DIR/playlist.m3u8"
  # 替换URL为本地文件名
  for url in $png_urls; do
    filename=$(basename "$url").ts
    awk -v old="$url" -v new="$filename" '{gsub(old, new); print}' "$TS_DIR/playlist.m3u8" > tmp.m3u8 && mv tmp.m3u8 "$TS_DIR/playlist.m3u8"
  done

  echo "已下载和转换所有ts文件，正在合并文件..." >> log.txt

  if ffmpeg -i "$TS_DIR/playlist.m3u8" -c copy "$FINAL_VIDEO"; then
    echo "最终视频 $FINAL_VIDEO 创建成功" >> log.txt
    cleanup_files
  else
    echo "创建视频失败." >> log.txt
  fi
}



while true; do
  # 用户交互，选择操作
  echo "请选择操作："
  echo "1. 创建下载任务"
  echo "2. 退出并清理"
  read -p "请输入选项（1/2）：" option
  # 根据用户选择执行相应操作
  case $option in
    1)
      read -p "请输入M3U8 URL：" m3u8_url
      read -p "请输入输出视频文件名：" output_video
      download "$m3u8_url" "$output_video"
      ;;
    2)
      cleanup_files
      echo "已清理临时文件，程序退出。"
      exit 0
      ;;
    *)
      echo "无效选项，程序退出。"
      ;;
  esac
done
