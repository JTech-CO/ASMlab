; Application runtime API: native L3 adapter or explicit development-only libc backend.
; See docs/RUNTIME-ABI.md. Do not expose FILE* or libc data in core code.
%ifndef ASMLAB_RT_API_INC
%define ASMLAB_RT_API_INC 1
extern rt_memcpy, rt_memmove, rt_memset, rt_memcmp
extern rt_strlen, rt_strnlen, rt_strcmp
extern rt_console_format, rt_console_puts, rt_output_flush, rt_is_tty
extern rt_input_stdin, rt_input_open_read, rt_input_close
extern rt_input_getc, rt_input_gets, rt_input_error
extern rt_decimal_from_cstr
%endif
