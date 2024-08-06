 Current libuv version : 1.48.0

 As of now i only tested it for windows.
 TCP functions does not work on windows. Casting overlapped to libuv request make a segfault

 see :
 Illegal instruction at address 0x102ab0
 src\win\core.c:585:0: 0x1012d8 in uv__poll (libuv.lib)
          req = uv__overlapped_to_req(overlappeds[i].lpOverlapped);

 Normally it should work on other platforms if i didn't make
 any errors translating the CMakeFiles.txt

 If you use it as shared lib, you must add "USING_UV_SHARED=1"
 in your define before import

 TODO/Questions :

     - Add the libuv tests to this build ?
     - See Solaris if
     - quid of OS390/OS400?
     - quid of QNX ?
     - No plans for cywin so no port : see https://github.com/ziglang/zig/issues/751#issuecomment-614272910
