import Crypto
import Vapor

public struct AuthenticatedUser {
    public let email: String
    public let name: String
    public let imageUrl: String?
}

public protocol NodesSSOAuthenticatable {
    static func authenticated(_ user: AuthenticatedUser, req: Request) -> Future<Response>
}

internal final class NodesSSOController<U: NodesSSOAuthenticatable> {
    internal func auth(_ req: Request) throws -> Future<Response> {
        let config: NodesSSOConfig = try req.make()

        guard config.skipSSO else {
            let url = config.redirectURL + "/" + config.environment.name
                + "?redirect_url=" + config.projectURL + config.callbackPath
        
            return Future.transform(to: req.redirect(to: url), on: req)
        }

        // Bypassing SSO
        let user = AuthenticatedUser(
            email: "autogenerated@like.st",
            name: "Autogenerated Test User",
            imageUrl: nil
        )
        return U.authenticated(user, req: req)
    }

    internal func callback(_ req: Request) throws -> Future<Response> {
        let config: NodesSSOConfig = try req.make()

        return try req
            .content
            .decode(Callback.self)
            .try { callback in
                let salt = config.salt.replacingOccurrences(of: "#email", with: callback.email)
                let expected = try SHA256.hash(salt).hexEncodedString()

                guard callback.token == expected else {
                    throw Abort(.unauthorized)
                }
            }
            .flatMap(to: Response.self) { callback in
                let user = AuthenticatedUser(
                    email: callback.email,
                    name: callback.name,
                    imageUrl: callback.image
                )
                return U.authenticated(user, req: req)
            }
    }
}

private extension NodesSSOController {
    struct Callback: Codable {
        let token: String
        let email: String
        let name: String
        let image: String?
    }
}