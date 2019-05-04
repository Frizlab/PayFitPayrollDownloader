/*
 * main.swift
 * test_payfit
 *
 * Created by François Lamboley on 2019/5/4.
 * Copyright © 2019 Frizlab. All rights reserved.
 */

import Foundation



enum PFAuthenticationError : Error {
	
	case communicationError
	case tooManyAccounts
	
	case unknownError
	
}


struct AuthInfo {
	
	var cookies: [HTTPCookie]
	var companyId: String
	var employeeId: String
	
}


class SessionDelegate : NSObject, URLSessionTaskDelegate {
	
	var cookies = [HTTPCookie]()
	
	func addCookies(from urlResponse: URLResponse?) {
		guard let httpResponse = urlResponse as? HTTPURLResponse else {return}
		addCookies(from: httpResponse.allHeaderFields, url: httpResponse.url)
	}
	
	func addCookies(from headers: [AnyHashable: Any], url: URL?) {
		if let headers = headers as? [String: String], let url = url {
			let cs = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
			for c in cs {
				cookies.removeAll(where: { $0.name == c.name })
			}
			cookies.append(contentsOf: cs)
		}
	}
	
	func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
		addCookies(from: response.allHeaderFields, url: task.currentRequest?.url)
		completionHandler(request)
	}
	
}


func authenticatePayFit(username: String, password: String) throws -> AuthInfo {
	struct SigninInfo : Encodable {
		let s = ""
		var email: String
		var password: String
		let language = "en"
		
		init(email e: String, password p: String) {
			email = e
			password = p
		}
	}
	
	
	let config = URLSessionConfiguration.ephemeral
	config.httpShouldSetCookies = false
	config.httpCookieAcceptPolicy = .never
	let sessionDelegate = SessionDelegate()
	let session = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
	
	let authURL = URL(string: "https://api.payfit.com/auth/signin")!
	var authRequest = URLRequest(url: authURL)
	authRequest.httpMethod = "POST"
	authRequest.addValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
	authRequest.httpBody = try JSONEncoder().encode(SigninInfo(email: username, password: password))
	guard let (authDataO, authResultO) = try? session.synchronousDataTask(with: authRequest), let authData = authDataO, let authResult = authResultO as? HTTPURLResponse else {
		throw PFAuthenticationError.communicationError
	}
	
	/* Checking (very succinctly) we're correctly authenticated */
	guard
		200..<300 ~= authResult.statusCode,
		let jsonObject = (try? JSONSerialization.jsonObject(with: authData, options: [])) as? [String: Any],
		let accounts = jsonObject["accounts"] as? [[String: Any?]]
	else {
		throw PFAuthenticationError.unknownError
	}
	
	guard let account = accounts.first, accounts.count == 1 else {
		throw PFAuthenticationError.tooManyAccounts
	}
	
	guard
		let idComponents = (account["id"] as? String).flatMap({ $0.split(separator: "/", omittingEmptySubsequences: false).map(String.init) }),
		idComponents.count == 2
	else {
		throw PFAuthenticationError.unknownError
	}
	
	let companyId = idComponents[0]
	let employeeId = idComponents[1]
	sessionDelegate.addCookies(from: authResult)
	
	var updateAccountURLComponents = URLComponents(string: "https://api.payfit.com/auth/updateCurrentAccount")!
	updateAccountURLComponents.queryItems = [
		URLQueryItem(name: "companyId", value: companyId),
		URLQueryItem(name: "employeeId", value: employeeId)
	]
	var updateAccountRequest = URLRequest(url: updateAccountURLComponents.url!)
	updateAccountRequest.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: sessionDelegate.cookies)
	guard
		let (updateAccountDataO, updateAccountResultO) = try? session.synchronousDataTask(with: updateAccountRequest),
		let _ = updateAccountDataO, let updateAccountResult = updateAccountResultO as? HTTPURLResponse,
		200..<300 ~= updateAccountResult.statusCode
	else {
		throw PFAuthenticationError.communicationError
	}
	
	return AuthInfo(cookies: sessionDelegate.cookies, companyId: companyId, employeeId: employeeId)
}

func performAPICall(session: URLSession, urlAsString: String, method: String = "GET") -> Data? {
	guard let url = URL(string: urlAsString) else {return nil}
	var request = URLRequest(url: url)
	request.httpMethod = method
	guard let (dataO, resultO) = try? session.synchronousDataTask(with: request), let data = dataO, let result = resultO as? HTTPURLResponse else {
		return nil
	}
	guard 200..<300 ~= result.statusCode else {return nil}
	return data
}

func performJSONAPICall<T : Decodable>(session: URLSession, urlAsString: String, method: String = "GET") -> T? {
	guard let data = performAPICall(session: session, urlAsString: urlAsString, method: method) else {return nil}
	return try? JSONDecoder().decode(T.self, from: data)
}


struct Payroll : Decodable {
	
	var absoluteMonth: Int
	var url: URL
	
}


let authInfo = try authenticatePayFit(username: "REDACTED", password: "REDACTED")

let config = URLSessionConfiguration.ephemeral
config.httpShouldSetCookies = false
config.httpCookieAcceptPolicy = .never
config.httpAdditionalHeaders = HTTPCookie.requestHeaderFields(with: authInfo.cookies)
	.merging(["x-payfit-id": authInfo.employeeId], uniquingKeysWith: { current, _ in current })
let session = URLSession(configuration: config)

guard let payrolls: [Payroll] = performJSONAPICall(session: session, urlAsString: "https://api.payfit.com/hr/employees/payrolls", method: "POST") else {
	exit(1)
}

let destinationFolderURL = URL(fileURLWithPath: "Desktop/Payrolls/", isDirectory: true, relativeTo: FileManager.default.homeDirectoryForCurrentUser)
try! FileManager.default.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true, attributes: nil)
for payroll in payrolls {
	let pdfURL = URL(fileURLWithPath: String(payroll.absoluteMonth) + ".pdf", isDirectory: false, relativeTo: destinationFolderURL)
	
	/* We skip already downloaded files */
	guard !FileManager.default.fileExists(atPath: pdfURL.path) else {continue}
	
	var urlComponents = URLComponents(url: payroll.url, resolvingAgainstBaseURL: true)!
	urlComponents.queryItems = urlComponents.queryItems ?? [] + [
		URLQueryItem(name: "attachment", value: "1")
	]
	guard let pdfData = performAPICall(session: session, urlAsString: urlComponents.url!.absoluteString) else {
		print("warning: skipping month \(payroll.absoluteMonth) because I can't retrieve the data")
		continue
	}
	guard let _ = try? pdfData.write(to: pdfURL) else {
		print("warning: cannot write pdf for month \(payroll.absoluteMonth) because of an unknown write error")
		continue
	}
}