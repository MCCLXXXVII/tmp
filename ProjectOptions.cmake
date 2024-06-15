include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(tmp_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(tmp_setup_options)
  option(tmp_ENABLE_HARDENING "Enable hardening" ON)
  option(tmp_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    tmp_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    tmp_ENABLE_HARDENING
    OFF)

  tmp_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR tmp_PACKAGING_MAINTAINER_MODE)
    option(tmp_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(tmp_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(tmp_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(tmp_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(tmp_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(tmp_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(tmp_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(tmp_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(tmp_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(tmp_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(tmp_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(tmp_ENABLE_PCH "Enable precompiled headers" OFF)
    option(tmp_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(tmp_ENABLE_IPO "Enable IPO/LTO" ON)
    option(tmp_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(tmp_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(tmp_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(tmp_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(tmp_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(tmp_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(tmp_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(tmp_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(tmp_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(tmp_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(tmp_ENABLE_PCH "Enable precompiled headers" OFF)
    option(tmp_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      tmp_ENABLE_IPO
      tmp_WARNINGS_AS_ERRORS
      tmp_ENABLE_USER_LINKER
      tmp_ENABLE_SANITIZER_ADDRESS
      tmp_ENABLE_SANITIZER_LEAK
      tmp_ENABLE_SANITIZER_UNDEFINED
      tmp_ENABLE_SANITIZER_THREAD
      tmp_ENABLE_SANITIZER_MEMORY
      tmp_ENABLE_UNITY_BUILD
      tmp_ENABLE_CLANG_TIDY
      tmp_ENABLE_CPPCHECK
      tmp_ENABLE_COVERAGE
      tmp_ENABLE_PCH
      tmp_ENABLE_CACHE)
  endif()

  tmp_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (tmp_ENABLE_SANITIZER_ADDRESS OR tmp_ENABLE_SANITIZER_THREAD OR tmp_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(tmp_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(tmp_global_options)
  if(tmp_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    tmp_enable_ipo()
  endif()

  tmp_supports_sanitizers()

  if(tmp_ENABLE_HARDENING AND tmp_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR tmp_ENABLE_SANITIZER_UNDEFINED
       OR tmp_ENABLE_SANITIZER_ADDRESS
       OR tmp_ENABLE_SANITIZER_THREAD
       OR tmp_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${tmp_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${tmp_ENABLE_SANITIZER_UNDEFINED}")
    tmp_enable_hardening(tmp_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(tmp_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(tmp_warnings INTERFACE)
  add_library(tmp_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  tmp_set_project_warnings(
    tmp_warnings
    ${tmp_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(tmp_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    tmp_configure_linker(tmp_options)
  endif()

  include(cmake/Sanitizers.cmake)
  tmp_enable_sanitizers(
    tmp_options
    ${tmp_ENABLE_SANITIZER_ADDRESS}
    ${tmp_ENABLE_SANITIZER_LEAK}
    ${tmp_ENABLE_SANITIZER_UNDEFINED}
    ${tmp_ENABLE_SANITIZER_THREAD}
    ${tmp_ENABLE_SANITIZER_MEMORY})

  set_target_properties(tmp_options PROPERTIES UNITY_BUILD ${tmp_ENABLE_UNITY_BUILD})

  if(tmp_ENABLE_PCH)
    target_precompile_headers(
      tmp_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(tmp_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    tmp_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(tmp_ENABLE_CLANG_TIDY)
    tmp_enable_clang_tidy(tmp_options ${tmp_WARNINGS_AS_ERRORS})
  endif()

  if(tmp_ENABLE_CPPCHECK)
    tmp_enable_cppcheck(${tmp_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(tmp_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    tmp_enable_coverage(tmp_options)
  endif()

  if(tmp_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(tmp_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(tmp_ENABLE_HARDENING AND NOT tmp_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR tmp_ENABLE_SANITIZER_UNDEFINED
       OR tmp_ENABLE_SANITIZER_ADDRESS
       OR tmp_ENABLE_SANITIZER_THREAD
       OR tmp_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    tmp_enable_hardening(tmp_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
