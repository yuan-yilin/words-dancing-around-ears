import Foundation
import SherpaOnnxC

/// sherpa-onnx 库链接探针：返回运行时版本信息（M1 验证用）
public enum SherpaOnnxInfo {
    public static var version: String {
        String(cString: SherpaOnnxGetVersionStr())
    }

    public static var gitSha1: String {
        String(cString: SherpaOnnxGetGitSha1())
    }

    public static var onnxruntimeVersion: String {
        String(cString: SherpaOnnxGetOnnxruntimeVersionStr())
    }
}
