Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location -LiteralPath $projectRoot

function Get-DisplayVersion {
    $dirty = -not [string]::IsNullOrEmpty((git status --porcelain))
    $exactTag = git describe --tags --match "v[0-9]*" --exact-match 2>$null
    if ($LASTEXITCODE -ne 0) { $exactTag = "" }
    $shortSha = git rev-parse --short=7 HEAD
    if (-not [string]::IsNullOrEmpty($exactTag)) {
        if ($dirty) { return "$exactTag^$shortSha" }
        return $exactTag
    }
    $lastTag = git describe --tags --match "v[0-9]*" --abbrev=0 2>$null
    if ($LASTEXITCODE -ne 0) { $lastTag = "" }
    if (-not [string]::IsNullOrEmpty($lastTag)) {
        if ($dirty) { return "$lastTag^$shortSha" }
        return "$lastTag-$shortSha"
    }
    if ($dirty) { return "v0.0.0^$shortSha" }
    return "v0.0.0-$shortSha"
}

function Get-BuildVersion {
    $exactTag = git describe --tags --match "v[0-9]*" --exact-match 2>$null
    if ($LASTEXITCODE -ne 0) { $exactTag = "" }
    if (-not [string]::IsNullOrEmpty($exactTag)) {
        if ($exactTag.StartsWith("v")) { return $exactTag.Substring(1) }
        return $exactTag
    }
    $lastTag = git describe --tags --match "v[0-9]*" --abbrev=0 2>$null
    if ($LASTEXITCODE -ne 0) { $lastTag = "" }
    $shortSha = git rev-parse --short=7 HEAD
    if (-not [string]::IsNullOrEmpty($lastTag)) {
        $base = $lastTag
        if ($base.StartsWith("v")) { $base = $base.Substring(1) }
        return "$base-$shortSha"
    }
    return "0.0.0-$shortSha"
}

$hostGoos = (go env GOHOSTOS).Trim()
$hostGoarch = (go env GOHOSTARCH).Trim()
$goos = if ($env:GOOS) { $env:GOOS } else { $hostGoos }
$goarch = if ($env:GOARCH) { $env:GOARCH } else { $hostGoarch }

switch ($goos) {
    "windows" { $defaultPlatform = "windows" }
    default { throw "dist-server.ps1 只能打包 Windows 目标, 当前 GOOS=$goos" }
}
switch ($goarch) {
    "amd64" { $defaultArch = "x86_64" }
    "arm64" { $defaultArch = "aarch64" }
    default { throw "不支持的 GOARCH: $goarch" }
}

$platform = if ($env:PLATFORM) { $env:PLATFORM } else { $defaultPlatform }
$arch = if ($env:ARCH) { $env:ARCH } else { $defaultArch }
if ($platform -ne $defaultPlatform -or $arch -ne $defaultArch) {
    throw "PLATFORM/ARCH 与 GOOS/GOARCH 不一致: $platform/$arch vs $goos/$goarch"
}

$version = if ($env:VERSION) { $env:VERSION } else { Get-BuildVersion }
$displayVersion = Get-DisplayVersion
if ([string]::IsNullOrWhiteSpace($version) -or $version.Contains("/") -or [string]::IsNullOrWhiteSpace($displayVersion)) {
    throw "无效的构建版本: $version / $displayVersion"
}

$distDir = if ($env:DIST_DIR) { $env:DIST_DIR } else { Join-Path $projectRoot "dist" }
New-Item -ItemType Directory -Force -LiteralPath $distDir | Out-Null
$archive = Join-Path $distDir "obooks-server-$version-$platform-$arch.zip"
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("obooks-server-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -LiteralPath $work | Out-Null
try {
    $binary = Join-Path $work "obooks-server.exe"
    if (Test-Path -LiteralPath $archive) {
        Remove-Item -LiteralPath $archive -Force
    }

    Write-Host "开始构建 obooks-server $displayVersion ($platform/$arch, $goos/$goarch)"
    go version
    $env:CGO_ENABLED = "0"
    $env:GOOS = $goos
    $env:GOARCH = $goarch
    go build -C server -trimpath -ldflags "-X main.version=$displayVersion" -o $binary ./cmd/obooks-server
    if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
        throw "缺少可执行文件: $binary"
    }

    $header = [System.IO.File]::ReadAllBytes($binary)
    if ($header.Length -lt 2 -or $header[0] -ne 0x4d -or $header[1] -ne 0x5a) {
        throw "PE 文件头无效: $binary"
    }

    if ($goos -eq $hostGoos -and $goarch -eq $hostGoarch) {
        $got = (& $binary --version).Trim()
        if ($got -ne $displayVersion) {
            throw "版本输出不正确: $got (期望 $displayVersion)"
        }
        Write-Host "版本检查通过: $got"
    }

    Compress-Archive -LiteralPath $binary -DestinationPath $archive -Force
    if (-not (Test-Path -LiteralPath $archive -PathType Leaf) -or (Get-Item -LiteralPath $archive).Length -le 0) {
        throw "归档生成失败: $archive"
    }
    Write-Host "已生成 $archive"
}
finally {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force
    }
}
