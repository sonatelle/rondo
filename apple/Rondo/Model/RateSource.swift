import Foundation

/// Fetching exchange rates from Frankfurter, and nothing else.
///
/// This is the one place Rondo reaches the network. It asks a single host
/// for a list of numbers, sends nothing about the person, and hands what
/// comes back to the core, which stores it and does every sum. The core
/// deliberately has no HTTP stack: every frontend would then carry one it
/// does not need, and the sandbox entitlement would sit in the wrong place.
///
/// Rates are always quoted against `baseCurrency()`, which the core owns.
/// Writing "EUR" on this side would be a second source of truth, and the
/// kind that goes wrong silently: change the core's base and this would go
/// on asking for the old one, storing numbers that no longer mean what the
/// column says they mean.
enum RateSource {
  /// Where the rates come from.
  ///
  /// Frankfurter publishes rates from central banks and other official
  /// sources, needs no key, and is open source with a self-hosted option
  /// if it ever stops answering. Its v2 API returns flat records; v1's
  /// nested shape is superseded and not used here.
  static let host = URL(string: "https://api.frankfurter.dev/v2/rates")!

  /// One published rate, exactly as the source gives it.
  ///
  /// `rate` is decoded straight into `Decimal` rather than through
  /// `Double`. At the four or five decimals a published rate usually
  /// carries the two agree - `Decimal(Double)` rounds back to the shortest
  /// form, so 1.1705 does survive one. They part company further out:
  /// 1.0000000001 comes back from a double as 1.0000000000999999488.
  /// Decoding directly costs nothing and is right at every length, so the
  /// question of how many digits a source publishes never has to be asked.
  /// `RateSourceTests` holds that, with a value long enough to tell.
  struct Quote: Decodable, Equatable {
    let date: String
    let base: String
    let quote: String
    let rate: Decimal
  }

  /// What went wrong, in terms a settings screen can show.
  enum Failure: Error, Equatable {
    /// The request never reached the host, or the connection dropped.
    case unreachable
    /// The host answered with something other than success.
    case refused(status: Int)
    /// The answer arrived but was not the shape this code knows.
    case unreadable
  }

  /// Rates for every day in `[from, to]`, oldest first.
  ///
  /// One request covers a whole span, which is what makes filling in a
  /// subscription's history a single call rather than one per charge.
  /// `quotes` narrows the answer to the currencies actually in use; asking
  /// for all 200 and discarding most would be slower for no gain.
  ///
  /// Days the source did not publish on are simply absent. That is not an
  /// error and must not be filled in: the core reads a rate as standing
  /// for every day until the next one, so a gap is already handled.
  static func rates(
    from: String,
    to: String,
    quotes: [String],
    session: URLSession = .shared
  ) async throws(Failure) -> [Quote] {
    var query = [
      URLQueryItem(name: "base", value: baseCurrency()),
      URLQueryItem(name: "from", value: from),
      URLQueryItem(name: "to", value: to),
    ]
    if !quotes.isEmpty {
      query.append(URLQueryItem(name: "quotes", value: quotes.joined(separator: ",")))
    }
    return try await fetch(query: query, session: session)
  }

  /// Rates for one day, or an empty list if the source skipped it.
  static func rates(
    on day: String,
    quotes: [String],
    session: URLSession = .shared
  ) async throws(Failure) -> [Quote] {
    var query = [
      URLQueryItem(name: "base", value: baseCurrency()),
      URLQueryItem(name: "date", value: day),
    ]
    if !quotes.isEmpty {
      query.append(URLQueryItem(name: "quotes", value: quotes.joined(separator: ",")))
    }
    return try await fetch(query: query, session: session)
  }

  private static func fetch(
    query: [URLQueryItem],
    session: URLSession
  ) async throws(Failure) -> [Quote] {
    var components = URLComponents(url: host, resolvingAgainstBaseURL: false)!
    components.queryItems = query
    guard let url = components.url else {
      throw .unreadable
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(from: url)
    } catch {
      // Offline, DNS, timeout, a dropped connection: from here they are
      // one thing, because there is one thing to do about any of them.
      throw .unreachable
    }
    if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
      throw .refused(status: http.statusCode)
    }
    do {
      return try JSONDecoder().decode([Quote].self, from: data)
    } catch {
      throw .unreadable
    }
  }
}

extension RateSource.Quote {
  /// This quote as the record the core stores.
  ///
  /// Marked as not hand-entered, which is what keeps a refresh from
  /// overwriting a rate somebody typed: the core refuses to.
  var stored: ExchangeRate {
    ExchangeRate(
      currency: quote,
      effectiveOn: date,
      rate: "\(rate)",
      isManual: false
    )
  }
}
