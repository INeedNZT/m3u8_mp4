# m3u8_mp4
A simple shell script - download m3u8 and convert to mp4 file

下载m3u8并且转换成mp4文件的简单脚本

## Get Started

`ffmpeg is required`

```
chmod +x m3u8_mp4.sh
```

```
./m3u8_mp4.sh
```
For those websites which use png file as container, you can try `m3u8_png_mp4.sh`

对于那些使用图床（png图片储存ts文件）的网站，可以尝试`m3u8_png_mp4.sh`

```
chmod +x m3u8_png_mp4.sh
```

```
./m3u8_png_mp4.sh
```

For those who have the need to download tasks in bulk, you can try using `m3u8_png_mp4_tasks.sh`. It is designed to be used in conjunction with `task.yml`, but you also have the option to specify your own task file by using `-t your_tasks.yml`.

对于那些有批量任务下载需求的，可以尝试使用`m3u8_png_mp4_tasks.sh`，它需要配合task.yml来使用，当然你也可以自己给它指定一个`-t your_tasks.yml`

```
chmod +x m3u8_png_mp4_tasks.sh
```

```
./m3u8_png_mp4_tasks.sh
```

## Space Issues

In individual downloads, you can add spaces to the workspace path by adding an escape character '\\', but escaping is not necessary within tasks.yml. It's important to note that spaces are not supported in output filenames.

在单个下载中，你可以通过添加转义符 '\\' 来给存储空间路径添加空格，但转义在tasks.yml中是不需要的。需要注意的是输出文件名不支持空格