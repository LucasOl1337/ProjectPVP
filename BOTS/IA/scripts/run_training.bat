@echo off
setlocal

REM Executa o treinamento genetico a partir da raiz do projeto
pushd "%~dp0\..\.." >nul 2>&1
if errorlevel 1 (
    echo [ERRO] Nao foi possivel acessar a pasta do projeto.
    pause
    exit /b 1
)

echo === Project PVP / IA Training ===
echo Pasta atual: %CD%

python -m pip install --quiet numpy >nul 2>&1
python tools\training_genetic_ga.py %*

popd >nul 2>&1
pause
