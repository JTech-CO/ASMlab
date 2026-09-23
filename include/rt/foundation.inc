; Storage-free ABI definitions for the independently linked foundation.
%ifndef ASMLAB_FOUNDATION_INC
%define ASMLAB_FOUNDATION_INC 1
%define RT_EINTR 4
%define RT_EIO 5
%define RT_EBADF 9
%define RT_EAGAIN 11
%define RT_EINVAL 22
%define RT_ENOSPC 28
%define RT_ERANGE 34
%define RT_IO_CAP 4096
%define RT_R_FD 0
%define RT_R_POS 8
%define RT_R_END 16
%define RT_R_STATUS 24
%define RT_R_BUF 32
%define RT_READER_SIZE (32+RT_IO_CAP)
%define RT_W_FD 0
%define RT_W_USED 8
%define RT_W_STATUS 16
%define RT_W_BUF 32
%define RT_WRITER_SIZE (32+RT_IO_CAP)
%endif
