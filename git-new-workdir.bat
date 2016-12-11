@echo off
setlocal

if "%~1" == "" goto :usage
if "%~2" == "" goto :usage

set orig_git="%~1"
set new_workdir="%~2"
set branch=%3

rem want to make sure that what is pointed to has a .git directory ...
pushd %orig_git% 2> nul
if errorlevel 1 (
	echo Not a git repository: %orig_git%
	goto :die
)

call :store_result git_dir "git rev-parse --git-dir"
if "%git_dir%" == "" (
	echo Not a git repository: %orig_git%
	goto :die
)

popd

if %git_dir% == ".git" (
	call :concat_path git_dir %orig_git% .git
) else if %git_dir% == "." (
	set git_dir=%orig_git%
)
call :concat_path conf_path %git_dir% config

rem don't link to a configured bare repository
call :store_result isbare "git --git-dir=%git_dir% config --bool --get core.bare"
if "%isbare%" == ""true"" (
	echo %git_dir% has core.bare set to true, remove from %conf_path% to use %~n0
	goto :die
)

rem don't link to a workdir
call :is_symlink %conf_path%
if errorlevel 1 (
	echo %orig_git% is a working directory only, please specify a complete repository.
	goto :die
)

rem make sure the links in the workdir have full paths to the original repo
call :to_fullpath git_dir %git_dir%
if errorlevel 1 (
	exit /b 1
)

rem don't recreate a workdir over an existing directory, unless it's empty
if exist %new_workdir%\ (
	call :count_files_and_dirs %new_workdir%
	if errorlevel 1 (
		echo destination directory %new_workdir% is not empty.
		goto :die
	)
	call :concat_path cleandir %new_workdir% .git
) else (
	set cleandir=%new_workdir%
)

call :concat_path new_git_dir %new_workdir% .git

mkdir %new_git_dir%
if errorlevel 1 (
	echo unable to create new workdir %new_workdir%!
	goto :die
)

call :to_fullpath cleandir %cleandir%
if errorlevel 1 (
	echo unable to create new workdir %new_workdir%!
	goto :die
)

rem create the links to the original repo.  explicitly exclude index, HEAD and
rem logs/HEAD from the list since they are purely related to the current working
rem directory, and should not be shared.
for %%x in (config refs logs/refs objects info hooks packed-refs remotes rr-cache svn) do (
	call :create_symlink %git_dir% %new_git_dir% %%x
	if errorlevel 1 (
		goto :failed
	)
)

rem commands below this are run in the context of the new workdir
pushd %new_workdir%
if errorlevel 1 (
	goto :failed
)

rem copy the HEAD from the original repository as a default branch
copy /y %git_dir%\HEAD .git\HEAD > nul
if errorlevel 1 (
	goto :failed
)

rem checkout the branch (either the same as HEAD from the original repository,
rem or the one that was asked for)
git --git-dir=.git checkout -f %branch%

exit /b


:usage
echo usage: %~n0 ^<repository^> ^<new_workdir^> [^<branch^>]
exit /b 127


:die
exit /b 128


:failed
echo unable to create new workdir %new_workdir%!
call :cleanup
exit /b 127


:store_result
for /f "tokens=*" %%i in ('%~2 2^> nul') do set %1="%%~i"
exit /b


:concat_path
call set %1="%%~2\%%~3"
exit /b


:is_symlink
setlocal
set attrs=%~a1
if "%attrs:~8,1%" == "l" (
	exit /b 1
)
exit /b 0


:to_fullpath
pushd "%~2"
if errorlevel 1 (
	exit /b 1
)
call set %1=%cd%
popd
exit /b 0


:count_files_and_dirs
setlocal
for /f "tokens=*" %%i in ('^(dir /b /a:-d %1 2^> nul ^& dir /b /a:d %1 2^> nul^) ^| find /c /v ""') do (
	set count=%%~i
)
exit /b %count%


:cleanup
rmdir /s /q %cleandir%
exit /b


:create_symlink
setlocal

call :concat_path src_dir %1 %3
call :concat_path dest_dir %2 %3

rem create a containing directory if needed
call :create_parent_dir %dest_dir%
if errorlevel 1 (
	exit /b
)

if exist %src_dir%\ (
	mklink /d %dest_dir% %src_dir% > nul
) else (
	mklink %dest_dir% %src_dir% > nul
)
if errorlevel 1 (
	exit /b
)

exit /b


:create_parent_dir
if exist "%~dp1" (
	exit /b 0
)

mkdir "%~dp1"
exit /b

