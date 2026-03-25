# Introduction
This is a work in progress toy implementation of a terminal emulator. I am using it as a learning project to improve my understanding of terminals, working with system calls, and working  
with Zig. This project is currently only for Linux, and only works with the ```dash``` shell. I plan to expand the functionality in the future
## Building and Running
This project requires both Zig 0.15.1 or later (for the source code) and CMake (for the C libraries) to be installed and on the system PATH.  
This project can be built by running ```zig build```. The ```build.zig``` file handles building with CMake automatically.
The output executable can be found in the ```/zig-out/bin/``` folder in the project's source directory.
## Credits  
This project uses glfw 3.4 which can be found here: https://github.com/glfw/glfw.
This project uses freetype version 2-14-2 which can be found here: https://gitlab.freedesktop.org/freetype/freetype.  
This project uses cglm which can be found here: https://github.com/recp/cglm.  

Many thanks to movq and Aram Drevekenin whose insightful blog posts found [here](https://movq.de/blog/postings/2018-02-24/0/POSTING-en.html) and  
[here](https://poor.dev/blog/terminal-anatomy/) greatly contributed to the development of this project.
