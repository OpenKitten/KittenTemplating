import PackageDescription

let package = Package(
    name: "KittenTemplating",
    dependencies: [
        .Package(url: "https://github.com/OpenKitten/MongoKitten.git", majorVersion: 3),
    ]
)
