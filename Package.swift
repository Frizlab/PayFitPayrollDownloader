// swift-tools-version:5.2
import PackageDescription


let package = Package(
	name: "payfit-payroll-downloader",
	platforms: [
		.macOS(.v10_14)
	],
	products: [
		.executable(name: "payfit-payroll-downloader", targets: ["payfit-payroll-downloader"])
	],
	dependencies: [
		.package(name: "GenericJSON", url: "https://github.com/zoul/generic-json-swift.git", from: "2.0.1")
	],
	targets: [
		.target(name: "payfit-payroll-downloader", dependencies: ["GenericJSON"])
	]
)
