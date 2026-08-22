import Foundation

// MARK: - Contacts

/// Address-book entries returned by `/api/contacts`.
///
/// The API has historically returned partially populated records, therefore
/// decoding is deliberately forgiving (and accepts numeric ids encoded as
/// either JSON numbers or strings).
struct Contact: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let email: String
    let notes: String?

    private enum CodingKeys: String, CodingKey { case id, name, email, notes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id))
            ?? (try? Int(c.decode(String.self, forKey: .id))) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }
}

/// A domain rule which controls automatic starring.  Unknown fields are
/// ignored so the model remains compatible with newer server responses.
struct ContactRule: Decodable, Identifiable, Hashable {
    let id: Int
    let domain: String
    let is_starred: Bool
    let enabled: Bool

    var isStarred: Bool { is_starred }

    private enum CodingKeys: String, CodingKey { case id, domain, is_starred, starred, enabled }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id))
            ?? (try? Int(c.decode(String.self, forKey: .id))) ?? 0
        domain = try c.decodeIfPresent(String.self, forKey: .domain) ?? ""
        is_starred = (try? c.decode(Bool.self, forKey: .is_starred))
            ?? (try? c.decode(Bool.self, forKey: .starred))
            ?? ((try? c.decode(Int.self, forKey: .is_starred)) == 1)
        enabled = (try? c.decode(Bool.self, forKey: .enabled))
            ?? ((try? c.decode(Int.self, forKey: .enabled)) != 0)
    }
}

// MARK: - User

struct User: Decodable, Identifiable {
    let id: Int
    let username: String
    let email: String
    let from_name: String?

    private enum CodingKeys: String, CodingKey {
        case id, username, email, from_name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        from_name = try c.decodeIfPresent(String.self, forKey: .from_name)
    }
}

// MARK: - Stats

struct Stats: Decodable {
    let inbound: Int
    let outbound: Int
    let starred: Int
    let unread: Int
    let spam: Int
    let trash: Int

    private enum CodingKeys: String, CodingKey {
        case inbound, outbound, starred, unread, spam, trash
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inbound = try c.decodeIfPresent(Int.self, forKey: .inbound) ?? 0
        outbound = try c.decodeIfPresent(Int.self, forKey: .outbound) ?? 0
        starred = try c.decodeIfPresent(Int.self, forKey: .starred) ?? 0
        unread = try c.decodeIfPresent(Int.self, forKey: .unread) ?? 0
        spam = try c.decodeIfPresent(Int.self, forKey: .spam) ?? 0
        trash = try c.decodeIfPresent(Int.self, forKey: .trash) ?? 0
    }
}

// MARK: - Folder

struct FolderItem: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let color: String?
    let icon: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, color, icon
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
    }
}

// MARK: - Email list

struct EmailSummary: Decodable, Identifiable {
    let id: Int
    let folder: String?
    let custom_folder_id: Int?
    let sender_name: String?
    let sender_email: String?
    let recipient: String?
    let subject: String?
    let preview: String?
    let is_starred: Int
    let is_read: Int
    let is_spam: Int
    let is_trash: Int
    let created_at: String?
    let received_at: String?

    var isStarred: Bool { is_starred == 1 }
    var isRead: Bool { is_read == 1 }

    private enum CodingKeys: String, CodingKey {
        case id, folder, custom_folder_id
        case sender_name, sender_email, recipient
        case subject, preview
        case is_starred, is_read, is_spam, is_trash
        case created_at, received_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        folder = try c.decodeIfPresent(String.self, forKey: .folder)
        custom_folder_id = try c.decodeIfPresent(Int.self, forKey: .custom_folder_id)
        sender_name = try c.decodeIfPresent(String.self, forKey: .sender_name)
        sender_email = try c.decodeIfPresent(String.self, forKey: .sender_email)
        recipient = try c.decodeIfPresent(String.self, forKey: .recipient)
        subject = try c.decodeIfPresent(String.self, forKey: .subject)
        preview = try c.decodeIfPresent(String.self, forKey: .preview)
        is_starred = try c.decodeIfPresent(Int.self, forKey: .is_starred) ?? 0
        is_read = try c.decodeIfPresent(Int.self, forKey: .is_read) ?? 0
        is_spam = try c.decodeIfPresent(Int.self, forKey: .is_spam) ?? 0
        is_trash = try c.decodeIfPresent(Int.self, forKey: .is_trash) ?? 0
        created_at = try c.decodeIfPresent(String.self, forKey: .created_at)
        received_at = try c.decodeIfPresent(String.self, forKey: .received_at)
    }
}

struct EmailPage: Decodable {
    let emails: [EmailSummary]
    let total: Int

    private enum CodingKeys: String, CodingKey {
        case emails, total
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        emails = try c.decodeIfPresent([EmailSummary].self, forKey: .emails) ?? []
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? emails.count
    }
}

// MARK: - Email detail

struct Attachment: Decodable, Identifiable, Hashable {
    let filename: String
    let content_type: String?

    var id: String { filename }

    private enum CodingKeys: String, CodingKey {
        case filename, content_type
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filename = try c.decodeIfPresent(String.self, forKey: .filename) ?? ""
        content_type = try c.decodeIfPresent(String.self, forKey: .content_type)
    }
}

struct EmailDetail: Decodable, Identifiable {
    let id: Int
    let folder: String?
    let custom_folder_id: Int?
    let sender_name: String?
    let sender_email: String?
    let recipient: String?
    let subject: String?
    let preview: String?
    let body_text: String?
    let body_html: String?
    let attachments: [Attachment]?
    let is_starred: Int
    let is_read: Int
    let is_spam: Int
    let is_trash: Int
    let created_at: String?
    let received_at: String?

    var isStarred: Bool { is_starred == 1 }

    private enum CodingKeys: String, CodingKey {
        case id, folder, custom_folder_id
        case sender_name, sender_email, recipient
        case subject, preview
        case body_text, body_html, attachments
        case is_starred, is_read, is_spam, is_trash
        case created_at, received_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        folder = try c.decodeIfPresent(String.self, forKey: .folder)
        custom_folder_id = try c.decodeIfPresent(Int.self, forKey: .custom_folder_id)
        sender_name = try c.decodeIfPresent(String.self, forKey: .sender_name)
        sender_email = try c.decodeIfPresent(String.self, forKey: .sender_email)
        recipient = try c.decodeIfPresent(String.self, forKey: .recipient)
        subject = try c.decodeIfPresent(String.self, forKey: .subject)
        preview = try c.decodeIfPresent(String.self, forKey: .preview)
        body_text = try c.decodeIfPresent(String.self, forKey: .body_text)
        body_html = try c.decodeIfPresent(String.self, forKey: .body_html)
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments)
        is_starred = try c.decodeIfPresent(Int.self, forKey: .is_starred) ?? 0
        is_read = try c.decodeIfPresent(Int.self, forKey: .is_read) ?? 0
        is_spam = try c.decodeIfPresent(Int.self, forKey: .is_spam) ?? 0
        is_trash = try c.decodeIfPresent(Int.self, forKey: .is_trash) ?? 0
        created_at = try c.decodeIfPresent(String.self, forKey: .created_at)
        received_at = try c.decodeIfPresent(String.self, forKey: .received_at)
    }
}

// MARK: - Send

struct SendResult: Decodable {
    let status: String?
    let id: String?
}
