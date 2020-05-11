// swift-tools-version:5.2
import PackageDescription


let package = Package(
	name: "payfit_payroll_downloader",
	platforms: [
		.macOS(.v10_14)
	],
	products: [
		.executable(name: "payfit_payroll_downloader", targets: ["payfit_payroll_downloader"])
	],
	dependencies: [
		.package(name: "GenericJSON", url: "https://github.com/zoul/generic-json-swift.git", from: "2.0.1")
	],
	targets: [
		.target(name: "payfit_payroll_downloader", dependencies: ["GenericJSON"])
	]
)
