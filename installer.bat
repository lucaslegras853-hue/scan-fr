@echo off
chcp 65001 >nul
title Scan FR - preparation du projet
cd /d "%~dp0"

where flutter >nul 2>nul || (echo Flutter introuvable. Ouvre ce fichier depuis un terminal ou Flutter marche. & pause & exit /b)

echo [1/4] Creation des fichiers Android manquants...
call flutter create --org com.lucas --project-name scan_fr --platforms android . >nul

echo [2/4] Permission internet et nom de l'appli...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch_android.ps1"

echo [3/4] Telechargement des modules...
call flutter pub get
if errorlevel 1 (
  echo Conflit de versions, on prend les plus recentes...
  call flutter pub upgrade --major-versions
)

echo [4/4] Construction de l'APK (quelques minutes la premiere fois)...
call flutter build apk --release
if errorlevel 1 (
  echo.
  echo La construction a echoue. Copie le message d'erreur a Claude.
  pause & exit /b
)

echo.
echo Termine ! L'APK est ici :
echo   %cd%\build\app\outputs\flutter-apk\app-release.apk
echo Envoie-le sur ton telephone et installe-le.
explorer build\app\outputs\flutter-apk
pause
