#define SANITIZER_OPTIONS_COMMON "exitcode=0:log_exe_name=true:allow_addr2line=true:fast_unwind_on_check=true:fast_unwind_on_fatal=true:log_to_syslog=true"
#define ASAN_OPTIONS SANITIZER_OPTIONS_COMMON ":log_path=/tmp/asan"
#define LSAN_OPTIONS SANITIZER_OPTIONS_COMMON ":log_path=/tmp/lsan:report_objects=true:log_threads=true:log_pointers=true"
__attribute__((visibility("default"))) const char *__asan_default_options() {
  return ASAN_OPTIONS;
}
__attribute__((visibility("default"))) const char *__lsan_default_options() {
  return LSAN_OPTIONS;
}
