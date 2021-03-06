//
//  OAuth1Swift.swift
//  OAuthSwift
//
//  Created by Dongri Jin on 6/22/14.
//  Copyright (c) 2014 Dongri Jin. All rights reserved.
//

import Foundation

// OAuthSwift errors
public let OAuthSwiftErrorDomain = "oauthswift.error"

public class OAuth1Swift: NSObject {

    public var client: OAuthSwiftClient
    public var version: OAuthSwiftCredential.Version { return self.client.credential.version }

    public var authorize_url_handler: OAuthSwiftURLHandlerType = OAuthSwiftOpenURLExternally.sharedInstance

    public var allowMissingOauthVerifier: Bool = false

    var consumer_key: String
    var consumer_secret: String
    var request_token_url: String
    var authorize_url: String
    var access_token_url: String

    var observer: AnyObject?

    public init(consumerKey: String, consumerSecret: String, requestTokenUrl: String, authorizeUrl: String, accessTokenUrl: String){
        self.consumer_key = consumerKey
        self.consumer_secret = consumerSecret
        self.request_token_url = requestTokenUrl
        self.authorize_url = authorizeUrl
        self.access_token_url = accessTokenUrl
        self.client = OAuthSwiftClient(consumerKey: consumerKey, consumerSecret: consumerSecret)
        self.client.credential.version = .OAuth1
    }
    
    public convenience init?(parameters: [String:String]){
        guard let consumerKey = parameters["consumerKey"], consumerSecret = parameters["consumerSecret"],
            requestTokenUrl = parameters["requestTokenUrl"], authorizeUrl = parameters["authorizeUrl"], accessTokenUrl = parameters["accessTokenUrl"] else {
            return nil
        }
        self.init(consumerKey:consumerKey, consumerSecret: consumerSecret,
          requestTokenUrl: requestTokenUrl,
          authorizeUrl: authorizeUrl,
          accessTokenUrl: accessTokenUrl)
    }

    struct CallbackNotification {
        static let notificationName = "OAuthSwiftCallbackNotificationName"
        static let optionsURLKey = "OAuthSwiftCallbackNotificationOptionsURLKey"
    }

    struct OAuthSwiftError {
        static let domain = "OAuthSwiftErrorDomain"
        static let appOnlyAuthenticationErrorCode = 1
    }

    public typealias TokenSuccessHandler = (credential: OAuthSwiftCredential, response: NSURLResponse) -> Void
    public typealias FailureHandler = (error: NSError) -> Void

    // 0. Start
    public func authorizeWithCallbackURL(callbackURL: NSURL, success: TokenSuccessHandler, failure: ((error: NSError) -> Void)) {
        self.postOAuthRequestTokenWithCallbackURL(callbackURL, success: {
            credential, response in

            self.observer = NSNotificationCenter.defaultCenter().addObserverForName(CallbackNotification.notificationName, object: nil, queue: NSOperationQueue.mainQueue(), usingBlock:{
                notification in
                //NSNotificationCenter.defaultCenter().removeObserver(self)
                NSNotificationCenter.defaultCenter().removeObserver(self.observer!)
                let url = notification.userInfo![CallbackNotification.optionsURLKey] as! NSURL
                var parameters: Dictionary<String, String> = Dictionary()
                if ((url.query) != nil){
                    parameters += url.query!.parametersFromQueryString()
                }
                if ((url.fragment) != nil && url.fragment!.isEmpty == false) {
                    parameters += url.fragment!.parametersFromQueryString()
                }
                if let token = parameters["token"] {
                    parameters["oauth_token"] = token
                }
                if (parameters["oauth_token"] != nil && (self.allowMissingOauthVerifier || parameters["oauth_verifier"] != nil)) {
                    //var credential: OAuthSwiftCredential = self.client.credential
                    self.client.credential.oauth_token = parameters["oauth_token"]!
                    if (parameters["oauth_verifier"] != nil) {
                        self.client.credential.oauth_verifier = parameters["oauth_verifier"]!
                    }
                    self.postOAuthAccessTokenWithRequestToken(success, failure: failure)
                } else {
                    let userInfo = [NSLocalizedDescriptionKey: "Oauth problem. oauth_token or oauth_verifier not returned"]
                    failure(error: NSError(domain: OAuthSwiftErrorDomain, code: -1, userInfo: userInfo))
                    return
                }
            })
            // 2. Authorize
            if let queryURL = NSURL(string: self.authorize_url + (self.authorize_url.has("?") ? "&" : "?") + "oauth_token=\(credential.oauth_token)") {
                self.authorize_url_handler.handle(queryURL)
            }
        }, failure: failure)
    }

    // 1. Request token
    public func postOAuthRequestTokenWithCallbackURL(callbackURL: NSURL, success: TokenSuccessHandler, failure: FailureHandler?) {
        var parameters =  Dictionary<String, AnyObject>()
        if let callbackURLString: String = callbackURL.absoluteString {
            parameters["oauth_callback"] = callbackURLString
        }
        self.client.post(self.request_token_url, parameters: parameters, success: {
            data, response in
            let responseString = NSString(data: data, encoding: NSUTF8StringEncoding) as String!
            let parameters = responseString.parametersFromQueryString()
            if let oauthToken=parameters["oauth_token"] {
                self.client.credential.oauth_token = oauthToken.safeStringByRemovingPercentEncoding
            }
            if let oauthTokenSecret=parameters["oauth_token_secret"] {
                self.client.credential.oauth_token_secret = oauthTokenSecret.safeStringByRemovingPercentEncoding
            }
            success(credential: self.client.credential, response: response)
        }, failure: failure)
    }

    // 3. Get Access token
    func postOAuthAccessTokenWithRequestToken(success: TokenSuccessHandler, failure: FailureHandler?) {
        var parameters = Dictionary<String, AnyObject>()
        parameters["oauth_token"] = self.client.credential.oauth_token
        parameters["oauth_verifier"] = self.client.credential.oauth_verifier
        self.client.post(self.access_token_url, parameters: parameters, success: {
            data, response in
            let responseString = NSString(data: data, encoding: NSUTF8StringEncoding) as String!
            let parameters = responseString.parametersFromQueryString()
            if let oauthToken=parameters["oauth_token"] {
                self.client.credential.oauth_token = oauthToken.safeStringByRemovingPercentEncoding
            }
            if let oauthTokenSecret=parameters["oauth_token_secret"] {
                self.client.credential.oauth_token_secret = oauthTokenSecret.safeStringByRemovingPercentEncoding
            }
            success(credential: self.client.credential, response: response)
        }, failure: failure)
    }

    public class func handleOpenURL(url: NSURL) {
        let notification = NSNotification(name: CallbackNotification.notificationName, object: nil,
            userInfo: [CallbackNotification.optionsURLKey: url])
        NSNotificationCenter.defaultCenter().postNotification(notification)
    }

}
