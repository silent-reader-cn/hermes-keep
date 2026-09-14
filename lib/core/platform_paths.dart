/// 平台语义路径工具（**一律不读宿主平台**）。
///
/// 平台判定是**决策输入**而非环境事实：宿主可能是 Linux/macOS（CI），
/// 而被测语义是 Windows。凡依赖平台的路径拼接都必须接受显式 `isWindows`，
/// 否则 Windows 语义用例会在非 Windows 宿主上假红（拼出的路径是 POSIX
/// 风格，注入的 fileExists 命不中）；反向也会让真实平台上的行为无法
/// 在本机复算。
///
/// 2026-09-14 CI 转绿专项：本文件即为「平台语义必须走注入接缝」的共享实现。
library;

/// 按平台语义取路径分隔符（不读 [Platform.pathSeparator]）。
String platformPathSeparator(bool isWindows) => isWindows ? '\\' : '/';

/// 取父目录，分隔符无关（同时认 `\` 与 `/`）。
///
/// 不能用 `File(path).parent`：它套用**宿主平台**路径规则，Linux 上对
/// `C:\Program Files\Hermes\hermes.exe` 取 parent 会得到 `.`，
/// 于是 `bundledWebuiAvailable()` 之类的 Windows 语义判定在 CI 上恒为假。
String platformParentDir(String path) {
  final back = path.lastIndexOf('\\');
  final slash = path.lastIndexOf('/');
  final idx = back > slash ? back : slash;
  return idx > 0 ? path.substring(0, idx) : path;
}
