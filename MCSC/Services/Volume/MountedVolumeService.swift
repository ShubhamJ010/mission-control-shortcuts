import Cocoa
import Foundation

/// Lightweight service for detecting and ejecting mounted disk image / removable volumes.
/// Uses NSWorkspace and FileManager with zero extra framework dependencies.
///
/// Memory profile: Zero heap allocations during idle. Queries are executed on-demand only.
protocol MountedVolumeServiceProtocol: AnyObject {
    /// Returns the mount path if `path` or `windowTitle` points inside an ejectable volume.
    func ejectableVolumePath(forDocumentPath path: String?, windowTitle: String?) -> String?

    /// Ejects the volume at `mountPath`. Async unmount with completion callback.
    func ejectVolume(at mountPath: String, completion: @escaping (Bool) -> Void)
}

final class MountedVolumeService: MountedVolumeServiceProtocol {
    func ejectableVolumePath(forDocumentPath path: String?, windowTitle: String?) -> String? {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey]
        let options: FileManager.VolumeEnumerationOptions = [.skipHiddenVolumes]
        let mountedURLs = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: options
        ) ?? []

        // Strategy 1: Match against mounted volume URLs using document path
        if let path, !path.isEmpty {
            let normalizedPath = path.hasSuffix("/") ? String(path.dropLast()) : path
            for volURL in mountedURLs {
                let volPath = volURL.path.hasSuffix("/") ? String(volURL.path.dropLast()) : volURL.path
                guard !volPath.isEmpty && volPath != "/" else { continue }
                if normalizedPath == volPath || normalizedPath.hasPrefix(volPath + "/"),
                   let values = try? volURL.resourceValues(forKeys: keys),
                   values.volumeIsEjectable == true || values.volumeIsRemovable == true {
                    return volURL.path
                }
            }

            // Fallback for paths explicitly starting with /Volumes/
            if normalizedPath.hasPrefix("/Volumes/") {
                let components = normalizedPath.split(separator: "/")
                if components.count >= 2 {
                    let candidate = "/Volumes/\(components[1])"
                    let candidateURL = URL(fileURLWithPath: candidate)
                    if let values = try? candidateURL.resourceValues(forKeys: keys),
                       values.volumeIsEjectable == true || values.volumeIsRemovable == true {
                        return candidate
                    }
                }
            }
        }

        // Strategy 2: Match window title against mounted ejectable volumes
        if let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            for volURL in mountedURLs {
                guard let values = try? volURL.resourceValues(forKeys: keys) else { continue }
                let isEjectable = values.volumeIsEjectable == true || values.volumeIsRemovable == true
                guard isEjectable else { continue }

                let volName = values.volumeName ?? volURL.lastPathComponent
                if volName.localizedCaseInsensitiveCompare(title) == .orderedSame ||
                    volURL.lastPathComponent.localizedCaseInsensitiveCompare(title) == .orderedSame {
                    return volURL.path
                }
            }
        }

        return nil
    }

    func ejectVolume(at mountPath: String, completion: @escaping (Bool) -> Void) {
        let url = URL(fileURLWithPath: mountPath)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                AppLogger.volume.info("Successfully ejected volume at '\(mountPath, privacy: .public)'")
                DispatchQueue.main.async {
                    completion(true)
                }
            } catch {
                AppLogger.volume
                    .error(
                        "Failed to eject volume at '\(mountPath, privacy: .public)': \(error.localizedDescription, privacy: .public)"
                    )
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }
}
