#!/bin/bash

# 这是 m3u8_png_mp4.sh 的批量下载版，可以处理多个下载任务，使用YAML文件配置下载任务
# 用法: m3u8_png_mp4_tasks.sh [-t task_file]
# 说明：ffmpeg -http_seekable 0 -i "$m3u8_url" -c:v copy -strict experimental "$output_path"
# 上面这个命令在有些网站可能会有问题，下载的视频可能会不全，所以放弃了这个命令，改用curl下载ts文件，然后用ffmpeg合并ts文件

DOWNLOAD_DIR="downloads"
TS_DIR="ts"
MAX_JOB_COUNT=15
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
  kill $(jobs -p) > /dev/null 2>&1
  # 中止已经运行的curl命令（根据临时存储空间的路径）
  pkill -f "curl.$tmp_workspace/$DOWNLOAD_DIR*" > /dev/null 2>&1
}

exit_and_cleanup() {
    cleanup_subprocesses
    cleanup_files
    echo "正在退出脚本..."
    exit
}

find_start () {
  offsets="$1"

  # 检查每个偏移量
  for offset in $offsets; do
    prev_offset=$offset
    for next_offset in $offsets; do
      if [ $next_offset -gt $prev_offset ]; then
        # 计算两个偏移量之间的差
        diff=$((next_offset - prev_offset))
        # 现在检查这个差是否正好等于188
        if [ $diff -eq 188 ]; then
          # 返回找到的ts文件的起始偏移量
          echo $((prev_offset))
          return
        fi
      fi
    done
  done
}

# 检查文件是否是ts文件或是否存在
check_files() {
  ts_paths=$(grep -E '^[^#].*[^[:space:]]' "$tmp_workspace/$TS_DIR/playlist.m3u8")
  for path in $ts_paths; do
    ffprobe -v error -show_format -i "$tmp_workspace/$TS_DIR/$path" >> "$tmp_workspace/log.txt" 2>&1
    if [ $? -ne 0 ]; then
      echo "文件 $path 不是ts文件或者文件不存在" >> "$tmp_workspace/log.txt"
      return 1
    fi
  done
  return 0
}

# 主要下载逻辑
download() {
  base_url=$(echo $m3u8_url | sed -E 's|(https?://[^/]+).*|\1|')
  dir_url=$(echo $m3u8_url | sed -E 's|/[^/]*$||')

  # 下载M3U8文件
  mkdir -p "$tmp_workspace/$DOWNLOAD_DIR"
  m3u8_file="$tmp_workspace/$DOWNLOAD_DIR/playlist.m3u8"
  curl -sS "$m3u8_url" -o "$m3u8_file"

  # 下载和转换PNG文件
  mkdir -p "$tmp_workspace/$TS_DIR"
  png_urls=$(grep -E '^[^#].*[^[:space:]]' "$tmp_workspace/$DOWNLOAD_DIR/playlist.m3u8")

  echo "发现: $(echo "$png_urls" | wc -l) 个资源文件需要下载" >> "$tmp_workspace/log.txt"

  file_index=0
  for url in $png_urls; do
    if [[ ! "$url" =~ ^http ]]; then
      # 不是/开头的，就是相对路径，需要加上dir_url
      if [[ ! "$url" =~ ^/ ]]; then
        url="$dir_url/$url"
      else
        url="${base_url}${url}"
      fi
    fi
    
    filename="segment_$((file_index++))"
    png_file="$tmp_workspace/$DOWNLOAD_DIR/$filename"
    ts_file="$tmp_workspace/$TS_DIR/${filename}.ts"

    while [ $(jobs -p | wc -l) -ge $MAX_JOB_COUNT ]; do
      # echo "已达到最大后台进程数，休眠1秒后重试" >> "$tmp_workspace/log.txt"
      sleep 1
    done
    
    (
      local attempts=0
      while [ $attempts -lt $MAX_ATTEMPTS ]; do
        # 加上-S参数来显示错误信息
        if curl -L "$url" -s -o "$png_file" && [ -s "$png_file" ]; then
          echo "下载 $url 成功" >> "$tmp_workspace/log.txt"
          # 用xxd判断文件开头16进制是否是标准的ts文件（47字节开头）
          if [ "$(xxd -l 1 -p "$png_file")" != "47" ]; then
            echo "正在转换 $filename 到ts文件..." >> "$tmp_workspace/log.txt"
            # 找到ts的开头，第一个合法的47字节
            matches=$(xxd -p -c 1 "$png_file" | grep -m 50 -n "47" | cut -d: -f1)
            start_offset=$(find_start "$matches")
            if [ -z "$start_offset" ]; then
              echo "未能找到元文件 $png_file 的起始偏移量，文件可能被加密或不是ts文件" >> "$tmp_workspace/log.txt"
            else
              echo "找到元文件 $png_file 的起始偏移量: $start_offset" >> "$tmp_workspace/log.txt"
              dd if="$png_file" of="$ts_file" bs=1 skip="$start_offset" > /dev/null 2>&1
              # 去除完开头多余的字节再验证是否是ts文件。有时候被封了，可能返回的是html文件或是其他格式的文件
              ffprobe -v error -show_format -i "$ts_file" 2>&1 | grep -q "format_name=mpegts"
              if [ $? -eq 0 ]; then
                echo "转换文件 $filename 成功" >> "$tmp_workspace/log.txt"
                break
              fi
            fi
            echo "转换ts文件失败，详情去ts目录下查看 $ts_file 是否存在以及它的内容" >> "$tmp_workspace/log.txt"
          else
            echo "$filename 是ts文件，直接复制到ts目录" >> "$tmp_workspace/log.txt"
            cp "$png_file" "$ts_file"
            break
          fi
        fi
        echo "第 $((attempts+1)) 次尝试下载或转换失败，5秒后重试" >> "$tmp_workspace/log.txt"
        sleep 5
        attempts=$((attempts+1))
      done
      if [ $attempts -eq $MAX_ATTEMPTS ]; then
          echo "下载 $workspace/$output_file.mp4 中的资源 $filename 失败，链接:$url" >> "$workspace/failed_downloads.txt"
      fi
    )&
  done

  # 等待所有后台任务完成
  wait

  # 先把原始的m3u8文件复制一份到ts目录下
  cp "$tmp_workspace/$DOWNLOAD_DIR/playlist.m3u8" "$tmp_workspace/$TS_DIR/playlist.m3u8"
  # 替换URL为本地文件名
  file_index=0
  for url in $png_urls; do
    filename="segment_$((file_index++)).ts"
    awk -v old="$url" -v new="$filename" '{gsub(old, new); print}' "$tmp_workspace/$TS_DIR/playlist.m3u8" > tmp.m3u8 && mv tmp.m3u8 "$tmp_workspace/$TS_DIR/playlist.m3u8"
  done

  # 如果存在failed_downloads.txt文件，并且包含output_file，说明有下载失败的资源
  if [ -f "$workspace/failed_downloads.txt" ]; then
    if grep -q "$output_file" "$workspace/failed_downloads.txt"; then
      echo "$workspace/$output_file.mp4存在下载失败的资源，不进行视频合并" >> "$tmp_workspace/log.txt"
      echo "视频下载失败，去 "$tmp_workspace/log.txt" 查看详情"
      return 1
    fi
  fi

  # 除了failed_downloads.txt文件，再次检查每个文件，看ts文件存不存在或者是不是ts文件
  check_files
  if [ $? -ne 0 ]; then
    echo "$workspace/$output_file.mp4存在下载失败的资源，不进行视频合并" >> "$tmp_workspace/log.txt"
    echo "视频下载失败，去 "$tmp_workspace/log.txt" 查看详情"
    return 1
  fi

  echo "已下载和转换所有ts文件，正在合并文件..." >> "$tmp_workspace/log.txt"

  ffmpeg -i "$tmp_workspace/$TS_DIR/playlist.m3u8" -c copy "$workspace/$output_file.mp4" >> "$tmp_workspace/log.txt" 2>&1
  if [ $? -eq 0 ]; then
    echo "视频下载成功！文件保存在 "$workspace/$output_file.mp4""
    cleanup_files
  else
    echo "视频合并失败" >> "$tmp_workspace/log.txt"
    echo "视频下载失败，去 "$tmp_workspace/log.txt" 查看详情"
    return 1
  fi
  return 0
}

# 默认的任务文件名
task_file="tasks.yml"

init_tasks() {
  # 如果文件不存在，则退出 
  if [ ! -f "$task_file" ]; then
    echo "任务文件不存在: $task_file"
    exit 1
  fi
  echo "找到任务文件: $task_file"

  # 读取任务文件列表（yml配置文件）
  declare -a workspace_map
  declare -a map_names
  paths="$(yq '.tasks[].workspace.path' $task_file)"
  i=0
  while IFS= read -r path; do
    declare -a "task_map_$i"_keys
    declare -a "task_map_$i"_values
    # 存储路径
    workspace_map+=("$path")
    # 存储映射名
    map_names+=("task_map_$i")
    tasks_str=$(yq '... comments="" | .tasks["'$i'"].workspace | del(.path)' $task_file)
    keys=$(echo "$tasks_str" | cut -d':' -f1)
    values=$(echo "$tasks_str" | cut -d':' -f2-)
    # 用制表符来区分键值对
    while IFS=$'\t' read -r key value; do
      eval "task_map_${i}_keys+=(\"$key\")"
      eval "task_map_${i}_values+=(\"$value\")"
    done <<< "$(paste <(echo "$keys") <(echo "$values"))"
    i=$((i+1))
  done <<< "$paths"

  # 开始处理任务
  for j in "${!workspace_map[@]}"; do
    workspace="${workspace_map[$j]}"
    echo "正在处理存储空间 $workspace 的下载任务..."
    init_workspace

    map_name="${map_names[$j]}"
    eval "keys=(\"\${${map_name}_keys[@]}\")"
    eval "values=(\"\${${map_name}_values[@]}\")"
    
    for k in "${!keys[@]}"; do
      output_file="${keys[$k]}"
      m3u8_url="${values[$k]}"
      # 去处首尾空格
      m3u8_url=$(echo "$m3u8_url" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
      # 初始化临时工作空间
      init_tmp_workspace
      echo "临时工作空间设置为: $tmp_workspace"
      # 设置信号处理
      trap exit_and_cleanup SIGINT SIGTERM
      # 开始下载任务
      echo "正在处理下载任务: $output_file , 请稍后..."
      download
      if [ $? -eq 0 ]; then
        echo "下载任务 $output_file 已完成"
      else
        echo "下载任务 $output_file 失败"
      fi
    done
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
