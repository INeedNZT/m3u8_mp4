#!/bin/bash

# 对于那些网站是m3u8却返回png的，可以尝试使用这个脚本下载
# 仅限于简单的的png->ts文件转换（去处png文件开头的212个字节），暂不支持加密文件的转换
#!/bin/bash

# 用户交互，选择操作
echo "请选择操作："
echo "1. 创建下载任务"
echo "2. 退出并清理"
read -p "请输入选项（1/2）：" option


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
}

# 主要下载逻辑
download() {
  M3U8_URL=$1  # M3U8链接
  FINAL_VIDEO=$2  # 输出视频文件名
  base_url=$(echo $M3U8_URL | sed -E 's|(https?://[^/]+).*|\1|')
  # 清理旧文件
  cleanup_files

  # 下载M3U8文件
  mkdir -p "$DOWNLOAD_DIR"
  m3u8_file="$DOWNLOAD_DIR/tmp.m3u8"
  curl "$M3U8_URL" -o "$m3u8_file"

  # 处理M3U8文件中的换行符
  sed 's/\r$//' $DOWNLOAD_DIR/tmp.m3u8 > $DOWNLOAD_DIR/playlist.m3u8
  rm $DOWNLOAD_DIR/tmp.m3u8

  # 下载和转换PNG文件
  mkdir -p "$TS_DIR"
  png_urls=$(grep -o '^[^#].*' "$DOWNLOAD_DIR/playlist.m3u8")

  echo "发现: $(echo "$png_urls" | wc -l) 个资源文件需要下载"

  for url in $png_urls; do
    if [[ ! "$url" =~ ^http ]]; then
      url="${base_url}${url}"
    fi
    
    filename=$(basename "$url")
    png_file="$DOWNLOAD_DIR/$filename"
    ts_file="$TS_DIR/${filename}.ts"

    while [ $(jobs -p | wc -l) -ge $MAX_JOB_COUNT ]; do
      echo "已达到最大后台进程数，休眠1秒后重试"
      sleep 1
    done
    
    (
      success=0
      attempts=0
      while [ $attempts -lt $MAX_ATTEMPTS ]; do
        if curl -L "$url" -o "$png_file" && [ -s "$png_file" ]; then
            echo "下载成功且文件非空，开始转换为TS格式"
            dd if="$png_file" of="$ts_file" bs=4 skip=53
            break
        else
            echo "第 $attempts 次尝试下载失败或文件为空，3秒后重试"
            sleep 3
            attempts=$((attempts+1))
        fi
      done
      if [ $attempts -eq $MAX_ATTEMPTS ]; then
          echo "$url" >> failed_downloads.txt
      fi
    )&
  done

  wait

  # 先把原始的m3u8文件复制一份到ts目录下
  cp "$DOWNLOAD_DIR/playlist.m3u8" "$TS_DIR/playlist.m3u8"
  # 替换URL为本地文件名
  for url in $png_urls; do
    filename=$(basename "$url").ts
    awk -v old="$url" -v new="$filename" '{gsub(old, new); print}' "$TS_DIR/playlist.m3u8" > tmp.m3u8 && mv tmp.m3u8 "$TS_DIR/playlist.m3u8"
  done

  echo "所有下载和转换操作已完成。"

  ffmpeg -i $TS_DIR/playlist.m3u8 -c copy $FINAL_VIDEO > /dev/null 2>&1 &

  echo "最终视频已创建: $FINAL_VIDEO"
}

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
    exit 1
    ;;
esac
