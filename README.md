# m3u8_mp4
A simple shell script - download m3u8 (Unencrypted) and convert to mp4 file

下载m3u8（未加密）并且转换成mp4文件的简单脚本

## Get Started

`ffmpeg ffprobe is required`

```
chmod +x m3u8_mp4.sh
```

```
./m3u8_mp4.sh
```

For those who have the need to download tasks in bulk, you can try using `m3u8_mp4_tasks.sh`. It is designed to be used in conjunction with `task.yml`, but you also have the option to specify your own task file by using `-t your_tasks.yml`.

对于那些有批量任务下载需求的，可以尝试使用`m3u8_mp4_tasks.sh`，它需要配合task.yml来使用，当然你也可以自己给它指定一个`-t your_tasks.yml`

```
chmod +x m3u8_mp4_tasks.sh
```

```
./m3u8_mp4_tasks.sh
```

## Space Issues

In individual downloads, you can add spaces to the workspace path by adding an escape character '\\', but escaping is not necessary within tasks.yml. It's important to note that spaces are not supported in output filenames.

在单个下载中，你可以通过添加转义符 '\\' 来给存储空间路径添加空格，但转义在tasks.yml中是不需要的。需要注意的是输出文件名不支持空格

## When the Resource Download Fails...

When a `failed_downloads.txt` file appears in the workspace directory, it indicates that there are resources in the m3u8 download list that cannot be downloaded. Generally, this occurs when the resources are denied or there is poor network connectivity, as each download task will attempt to retry 5 times. Detailed logs can be found in `log.txt` for troubleshooting. You may switch networks, then reacquire a new m3u8 link and retry the failed download task.

当存储空间中出现`failed_downloads.txt`文件时，这意味着m3u8下载列表中存在着无法下载的资源。一般情况下出现这种情况是资源被拒或者网络情况不好，因为每个下载任务会重试5次。可以在`log.txt`看到详细日志来排查。你可以尝试换个网络，重新获取新的m3u8链接，然后再重试那个失败的下载任务。

### Another Tip

If you frequently encounter request failures and have ruled out issues on the server side, you might consider lowering the `MAX_JOB_COUNT` in your script. A range between 5 to 10 is a relatively conservative interval for this setting.

如果经常发生请求失败，排除服务器端的问题后，可以尝试把脚本中的 `MAX_JOB_COUNT` 调低，5到10之间是一个相对保守的区间。