import Foundation
import Darwin

/// The kernel releases this lock on process exit, including crashes. Keeping the
/// file avoids creating two lock inodes while applications from different paths race.
final class InstanceLock {
    private var descriptor: Int32 = -1
    func acquire(at url: URL) -> Bool {
        guard descriptor == -1 else { return true }
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return false }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return false }
        descriptor = fd
        return true
    }
    deinit { if descriptor >= 0 { close(descriptor) } }
}
