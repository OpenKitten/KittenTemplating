import PackageDescription

let package = Package(
    name: "KittenTemplating",
    dependencies: [
        .Package(url: "https://github.com/OpenKitten/BSON.git", majorVersion: 4),
    ]
)
