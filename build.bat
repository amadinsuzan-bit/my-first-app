@echo off
setlocal DisableDelayedExpansion
setlocal EnableExtensions



pushd "%~dp0" || exit /b 1
set "MVNW=mvnw.cmd"

SET "CMD=%~1"
REM No argument is what a first-time developer actually runs -- on Windows it is
REM literally what a double-click does -- and it has to be the cloud build. It
REM used to build a local jar: that never contacts the build server, never signs
REM in, exits 0 and prints BUILD SUCCESS, so someone following the onboarding
REM checklist was told they had succeeded while the server saw nothing at all.
if "%CMD%"=="" (
  echo Building your first CLOUD build ^(javascript^). A browser will open for sign-in.
  echo For a local jar instead, run .\build.bat jar -- see .\build.bat help for every target.
  set CMD=javascript
)
REM --- first-build signals ---------------------------------------------------
REM Tells cloud.codenameone.com when this starter starts a build and how Maven
REM exited, so a first build that dies on this machine (no JDK, an old JDK, a
REM Maven download, a compile error) is visible to us instead of silent. Sends
REM ONLY: this starter's package id, the target, "windows", the Java major
REM version, the exit code, one word for the failure class and the duration.
REM Never your code, paths, user name or output.
REM Opt out with: set CN1_TELEMETRY=0
set "CN1_STARTER_PACKAGE=co.cn1.my.first.app.dp3oo5vf"
if not defined CN1_EVENTS_URL set "CN1_EVENTS_URL=https://cloud.codenameone.com/api/v2/onboarding/starter-event"
REM Maven reports IDE builds itself (cn1.telemetry.* in pom.xml); this tells it the
REM launcher is already reporting this one, so it is counted once.
set "CN1_LAUNCHER=1"
set "CN1_TARGET=%CMD%"
set "CN1_JAVA=none"
set "CN1_JAVA_EXE=java"
if defined JAVA_HOME set "CN1_JAVA_EXE=%JAVA_HOME%\bin\java"
for /f "tokens=3" %%v in ('call "%CN1_JAVA_EXE%" -version 2^>^&1 ^| findstr /i "version"') do set "CN1_JAVA=%%~v"
for /f "tokens=1,2 delims=." %%a in ("%CN1_JAVA%") do (
  if "%%a"=="1" (set "CN1_JAVA=%%b") else (set "CN1_JAVA=%%a")
)
REM Start time in epoch seconds, for the duration reported at exit. cmd has no
REM clock arithmetic, so ask PowerShell (present on every supported Windows).
set "CN1_START="
if not "%CN1_TELEMETRY%"=="0" for /f %%s in ('powershell -NoProfile -NonInteractive -Command "[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()" 2^>nul') do set "CN1_START=%%s"
if /i not "%CMD%"=="help" call :cn1_event "step=launch" "exit=" "reason=" "secs="

goto %CMD%

goto :finish
:mac_desktop
call "%MVNW%" package -DskipTests -Dcodename1.platform^=javase -Dcodename1.buildTarget^=mac-os-x-desktop -U -e

goto :finish
:mac_native
call "%MVNW%" package -DskipTests -Dcodename1.platform^=ios -Dcodename1.buildTarget^=mac-os-x-native -U -e

goto :finish
:mac_catalyst
call "%MVNW%" package -DskipTests -Dcodename1.platform^=ios -Dcodename1.buildTarget^=mac-catalyst -U -e

goto :finish
:windows_desktop
call "%MVNW%" package -DskipTests -Dcodename1.platform^=javase -Dcodename1.buildTarget^=windows-desktop -U -e

goto :finish
:windows_device
call "%MVNW%" package -DskipTests -Dcodename1.platform^=win -Dcodename1.buildTarget^=windows-device -U -e

goto :finish
:linux_device
call "%MVNW%" package -DskipTests -Dcodename1.platform^=linux -Dcodename1.buildTarget^=linux-device -U -e

goto :finish
:javascript
call "%MVNW%" package -DskipTests -Dcodename1.platform^=javascript -Dcodename1.buildTarget^=javascript -U -e

goto :finish
:android
call "%MVNW%" package -DskipTests -Dcodename1.platform^=android -Dcodename1.buildTarget^=android-device -U -e

goto :finish
:xcode
call "%MVNW%" package -DskipTests -Dcodename1.platform^=ios -Dcodename1.buildTarget^=ios-source -U -e

goto :finish
:ios_source
goto :xcode

:android_source
call "%MVNW%" package -DskipTests -Dcodename1.platform^=android -Dcodename1.buildTarget^=android-source -U -e

goto :finish
:ios
call "%MVNW%" package -DskipTests -Dcodename1.platform^=ios -Dcodename1.buildTarget^=ios-device -U -e

goto :finish
:ios_release
call "%MVNW%" package -DskipTests -Dcodename1.platform^=ios -Dcodename1.buildTarget^=ios-device-release -U -e

goto :finish
:jar
call "%MVNW%" -Pexecutable-jar package -Dcodename1.platform^=javase -DskipTests -U -e

goto :finish
:help
echo .\build.bat [COMMAND]
echo Local Build Commands:
echo   The following commands will build the app locally ^(i.e. does NOT use the Codename One build server^)
echo 
echo   jar
echo     Builds app as desktop app executable jar file to javase/target directory
echo   android_source
echo     Generates an android gradle project that can be opened in Android studio
echo     *Requires android development tools installed.
echo     *Requires ANDROID_HOME environment variable
echo     *Requires either GRADLE_HOME environment variable^, or for gradle to be in PATH
echo   ios_source
echo     Generates an Xcode Project that you can open and build using Apple^'s development tools
echo     *Requires a Mac with Xcode installed
echo 
echo Build Server Commands:
echo   The following commands will build the app using the Codename One build server^, and require
echo   a Codename One account.  See https://www.codenameone.com
echo 
echo   ios
echo     Builds iOS app.
echo   ios_release
echo     Builds iOS app for submission to Apple appstore.
echo   android
echo     Builds android app.
echo   mac_desktop
echo     Builds Mac OS desktop app.
echo     *Mac OS Desktop builds are a Pro user feature.
echo   mac_native
echo     Builds a native Mac app ^(no JVM^).
echo   windows_desktop
echo     Builds Windows desktop app.
echo     *Windows Desktop builds are a Pro user feature.
echo   windows_device
echo     Builds a native Windows app ^(no JVM^).
echo   linux_device
echo     Builds a native Linux app ^(ELF^, no JVM^).
echo   javascript
echo     Builds as a web app.

goto :finish
:settings
call "%MVNW%" cn1:settings -U -e

:finish
set "CN1_EXIT_CODE=%errorlevel%"
REM Why it stopped. build.sh reads Maven's output for this; cmd cannot tee it
REM without hiding it from the developer, so here the class comes from what was
REM checked before the build: no JDK, or one older than the 17 the starter
REM needs, are the two failures a first-timer hits most and both are known
REM without the log. Anything else is reported as build_failed.
set "CN1_REASON=build_failed"
if "%CN1_JAVA%"=="none" set "CN1_REASON=no_jdk"
set "CN1_JMAJ=0"
set /a CN1_JMAJ=%CN1_JAVA% >nul 2>&1
if not "%CN1_JAVA%"=="none" if %CN1_JMAJ% GTR 0 if %CN1_JMAJ% LSS 17 set "CN1_REASON=java_too_old"
if "%CN1_EXIT_CODE%"=="0" set "CN1_REASON=ok"
set "CN1_SECS="
if defined CN1_START for /f %%s in ('powershell -NoProfile -NonInteractive -Command "[DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - %CN1_START%" 2^>nul') do set "CN1_SECS=%%s"
if /i not "%CN1_TARGET%"=="help" call :cn1_event "step=exit" "exit=%CN1_EXIT_CODE%" "reason=%CN1_REASON%" "secs=%CN1_SECS%"
popd
exit /b %CN1_EXIT_CODE%

REM Fire-and-forget: three seconds at most, and a failure is never an error.
:cn1_event
if "%CN1_TELEMETRY%"=="0" goto :eof
where curl.exe >nul 2>&1 || goto :eof
curl.exe -s -o nul -m 3 -X POST "%CN1_EVENTS_URL%" --data-urlencode "pkg=%CN1_STARTER_PACKAGE%" --data-urlencode "target=%CN1_TARGET%" --data-urlencode "os=windows" --data-urlencode "java=%CN1_JAVA%" --data-urlencode %1 --data-urlencode %2 --data-urlencode %3 --data-urlencode %4 >nul 2>&1
goto :eof
