import Foundation

enum SVGRepositorySyncError: LocalizedError {
    case invalidRepositoryURL
    case unsupportedHost
    case missingRepositoryPath
    case invalidServerResponse
    case repositoryNotFound
    case missingDefaultBranch
    case missingImageDirectory
    case noSVGFilesFound

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryURL:
            return "The repository URL is not valid."
        case .unsupportedHost:
            return "Only github.com repository URLs are supported."
        case .missingRepositoryPath:
            return "Repository URL must include owner and repository name."
        case .invalidServerResponse:
            return "Unexpected response from GitHub."
        case .repositoryNotFound:
            return "Repository was not found or is not accessible."
        case .missingDefaultBranch:
            return "Unable to determine the repository default branch."
        case .missingImageDirectory:
            return "Could not find keymap-drawer/img in the repository."
        case .noSVGFilesFound:
            return "No SVG files were found in keymap-drawer/img."
        }
    }
}

private struct ParsedRepository {
    let owner: String
    let name: String
    let branch: String?
}

private struct GitHubRepositoryResponse: Decodable {
    let defaultBranch: String

    enum CodingKeys: String, CodingKey {
        case defaultBranch = "default_branch"
    }
}

private struct GitHubBranchEntry: Decodable {
    let name: String
}

private struct GitHubContentEntry: Decodable {
    let name: String
    let path: String
    let type: String
    let downloadURL: String?

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case type
        case downloadURL = "download_url"
    }
}

struct SVGSyncResult {
    let assets: [SVGAsset]
    let branch: String
}

struct RepositoryBranchCatalog {
    let branches: [String]
    let defaultBranch: String?
    let urlBranch: String?
}

final class SVGRepositorySyncService {
    private let session: URLSession
    private let fileManager: FileManager

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    func sync(repositoryURL: String, preferredBranch: String? = nil) async throws -> SVGSyncResult {
        let parsed = try parseRepositoryURL(repositoryURL)
        let branch = try await resolveBranch(for: parsed, preferredBranch: preferredBranch)
        let entries = try await fetchImageEntries(owner: parsed.owner, repository: parsed.name, branch: branch)

        let svgEntries = entries
            .filter { $0.type == "file" && $0.name.lowercased().hasSuffix(".svg") && $0.downloadURL != nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard !svgEntries.isEmpty else {
            throw SVGRepositorySyncError.noSVGFilesFound
        }

        let destination = try makeDestinationDirectory(owner: parsed.owner, repository: parsed.name, branch: branch)

        var assets: [SVGAsset] = []
        for entry in svgEntries {
            guard let downloadURL = entry.downloadURL else { continue }
            let data = try await downloadFile(at: downloadURL)

            let localURL = destination.appendingPathComponent(entry.name)
            try data.write(to: localURL, options: .atomic)

            assets.append(
                SVGAsset(
                    id: entry.path,
                    fileName: entry.name,
                    sourceURL: downloadURL,
                    localFilePath: localURL.path
                )
            )
        }

        return SVGSyncResult(assets: assets, branch: branch)
    }

    func fetchBranches(repositoryURL: String) async throws -> RepositoryBranchCatalog {
        let parsed = try parseRepositoryURL(repositoryURL)
        let repositoryInfo = try await fetchRepository(owner: parsed.owner, repository: parsed.name)
        let branches = try await fetchBranchNames(owner: parsed.owner, repository: parsed.name)

        var unique = Array(Set(branches)).sorted()
        if !repositoryInfo.defaultBranch.isEmpty, !unique.contains(repositoryInfo.defaultBranch) {
            unique.insert(repositoryInfo.defaultBranch, at: 0)
        }

        if let urlBranch = parsed.branch, !urlBranch.isEmpty, !unique.contains(urlBranch) {
            unique.insert(urlBranch, at: 0)
        }

        return RepositoryBranchCatalog(
            branches: unique,
            defaultBranch: repositoryInfo.defaultBranch.isEmpty ? nil : repositoryInfo.defaultBranch,
            urlBranch: parsed.branch
        )
    }

    private func parseRepositoryURL(_ rawURL: String) throws -> ParsedRepository {
        guard let url = URL(string: rawURL) else {
            throw SVGRepositorySyncError.invalidRepositoryURL
        }

        guard let host = url.host?.lowercased() else {
            throw SVGRepositorySyncError.invalidRepositoryURL
        }

        let normalizedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard normalizedHost == "github.com" else {
            throw SVGRepositorySyncError.unsupportedHost
        }

        let parts = url.path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else {
            throw SVGRepositorySyncError.missingRepositoryPath
        }

        let owner = parts[0]
        var repository = parts[1]
        if repository.lowercased().hasSuffix(".git") {
            repository.removeLast(4)
        }

        guard !owner.isEmpty, !repository.isEmpty else {
            throw SVGRepositorySyncError.missingRepositoryPath
        }

        var branch: String?
        if parts.count >= 4, parts[2].lowercased() == "tree" {
            let rawBranch = parts.dropFirst(3).joined(separator: "/")
            branch = rawBranch.removingPercentEncoding ?? rawBranch
        }

        return ParsedRepository(owner: owner, name: repository, branch: branch)
    }

    private func resolveBranch(for repository: ParsedRepository, preferredBranch: String?) async throws -> String {
        if let preferredBranch = preferredBranch?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preferredBranch.isEmpty {
            return preferredBranch
        }

        if let branch = repository.branch, !branch.isEmpty {
            return branch
        }

        let repositoryInfo = try await fetchRepository(owner: repository.owner, repository: repository.name)
        guard !repositoryInfo.defaultBranch.isEmpty else {
            throw SVGRepositorySyncError.missingDefaultBranch
        }

        return repositoryInfo.defaultBranch
    }

    private func fetchRepository(owner: String, repository: String) async throws -> GitHubRepositoryResponse {
        let endpoint = "https://api.github.com/repos/\(owner)/\(repository)"
        var request = URLRequest(url: try makeURL(endpoint))
        request.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.addValue("Keylens", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        let http = try validateJSONResponse(response)

        if http.statusCode == 404 {
            throw SVGRepositorySyncError.repositoryNotFound
        }

        guard (200 ... 299).contains(http.statusCode) else {
            throw SVGRepositorySyncError.invalidServerResponse
        }

        return try JSONDecoder().decode(GitHubRepositoryResponse.self, from: data)
    }

    private func fetchBranchNames(owner: String, repository: String) async throws -> [String] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(owner)/\(repository)/branches"
        components.queryItems = [URLQueryItem(name: "per_page", value: "100")]

        guard let url = components.url else {
            throw SVGRepositorySyncError.invalidRepositoryURL
        }

        var request = URLRequest(url: url)
        request.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.addValue("Keylens", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        let http = try validateJSONResponse(response)

        if http.statusCode == 404 {
            throw SVGRepositorySyncError.repositoryNotFound
        }

        guard (200 ... 299).contains(http.statusCode) else {
            throw SVGRepositorySyncError.invalidServerResponse
        }

        let decoded = try JSONDecoder().decode([GitHubBranchEntry].self, from: data)
        return decoded.map(\.name).filter { !$0.isEmpty }
    }

    private func fetchImageEntries(owner: String, repository: String, branch: String) async throws -> [GitHubContentEntry] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(owner)/\(repository)/contents/keymap-drawer/img"
        components.queryItems = [URLQueryItem(name: "ref", value: branch)]

        guard let url = components.url else {
            throw SVGRepositorySyncError.invalidRepositoryURL
        }

        var request = URLRequest(url: url)
        request.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.addValue("Keylens", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        let http = try validateJSONResponse(response)

        if http.statusCode == 404 {
            throw SVGRepositorySyncError.missingImageDirectory
        }

        guard (200 ... 299).contains(http.statusCode) else {
            throw SVGRepositorySyncError.invalidServerResponse
        }

        if let entries = try? JSONDecoder().decode([GitHubContentEntry].self, from: data) {
            return entries
        }

        if let singleEntry = try? JSONDecoder().decode(GitHubContentEntry.self, from: data) {
            return [singleEntry]
        }

        throw SVGRepositorySyncError.invalidServerResponse
    }

    private func downloadFile(at rawURL: String) async throws -> Data {
        var request = URLRequest(url: try makeURL(rawURL))
        request.addValue("Keylens", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        let http = try validateJSONResponse(response)

        guard (200 ... 299).contains(http.statusCode) else {
            throw SVGRepositorySyncError.invalidServerResponse
        }

        return data
    }

    private func makeDestinationDirectory(owner: String, repository: String, branch: String) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let sanitized = "\(owner)_\(repository)_\(branch)".replacingOccurrences(of: "/", with: "_")
        let directory = appSupport
            .appendingPathComponent("Keylens", isDirectory: true)
            .appendingPathComponent("DownloadedSVG", isDirectory: true)
            .appendingPathComponent(sanitized, isDirectory: true)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let existing = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in existing where file.pathExtension.lowercased() == "svg" {
            try? fileManager.removeItem(at: file)
        }

        return directory
    }

    private func makeURL(_ rawURL: String) throws -> URL {
        guard let url = URL(string: rawURL) else {
            throw SVGRepositorySyncError.invalidRepositoryURL
        }
        return url
    }

    private func validateJSONResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw SVGRepositorySyncError.invalidServerResponse
        }

        return http
    }
}
