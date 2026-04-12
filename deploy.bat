@echo off
set SRC=F:\Cebulator
set DST=F:\World of Warcraft\_retail_\Interface\AddOns\Cebulator

xcopy "%SRC%\*.lua" "%DST%\" /Y
xcopy "%SRC%\*.xml" "%DST%\" /Y
xcopy "%SRC%\*.toc" "%DST%\" /Y
xcopy "%SRC%\*.tga" "%DST%\" /Y
xcopy "%SRC%\*.png" "%DST%\" /Y
xcopy "%SRC%\libs" "%DST%\libs" /E /Y /I

echo Done.
pause
