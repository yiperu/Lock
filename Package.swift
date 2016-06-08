import PackageDescription

let package = Package(
    name: "Lock",
    dependencies: [
        .Package(url: "https://github.com/PureSwift/GATT.git", majorVersion: 1),
        .Package(url: "https://github.com/ColemanCDA/CryptoSwift", majorVersion: 1),
        .Package(url: "https://github.com/OpenKitten/BSON.git", majorVersion: 3)
    ],
    targets: [
        Target(
            name: "lockd",
            dependencies: [.Target(name: "CoreLock")]
        ),
        Target(
            name: "CoreLockUnitTests",
            dependencies: [.Target(name: "CoreLock")]
        ),
        Target(
            name: "CoreLock"
        )
    ],
    exclude: ["Xcode", "Android"]
)