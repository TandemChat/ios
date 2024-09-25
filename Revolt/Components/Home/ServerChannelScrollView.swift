//
//  ServerChannelScrollView.swift
//  Revolt
//
//  Created by Angelo on 2023-11-25.
//

import SwiftUI
import Types


struct ChannelListItem: View {
    @EnvironmentObject var viewState: ViewState
    var server: Server
    var channel: Channel
    
    @State var inviteSheetUrl: InviteUrl? = nil
    
    var body: some View {
        let isSelected = viewState.currentChannel.id == channel.id
        let unread = viewState.getUnreadCountFor(channel: channel)

        let foregroundColor = isSelected || unread != nil ? viewState.theme.foreground : viewState.theme.foreground3
        let backgroundColor = isSelected ? viewState.theme.background : viewState.theme.background2
        
        Button {
            viewState.selectChannel(inServer: server.id, withId: channel.id)
        } label: {
            HStack {
                ChannelIcon(channel: channel)
                    .fontWeight(.medium)
                
                Spacer()
                
                if let unread = unread {
                    UnreadCounter(unread: unread)
                        .padding(.trailing)
                }
            }
            .padding(8)
        }
        .contextMenu {
            Button("Mark as read") {
                Task {
                    if let last_message = viewState.channelMessages[channel.id]?.last {
                        try! await viewState.http.ackMessage(channel: channel.id, message: last_message).get()
                    }
                }
            }
            
            Button("Notification options") {
                viewState.path.append(NavigationDestination.channel_info(channel.id))
            }
            
            Button("Create Invite") {
                Task {
                    let res = await viewState.http.createInvite(channel: channel.id)
                    
                    if case .success(let invite) = res {
                        inviteSheetUrl = InviteUrl(url: URL(string: "https://rvlt.gg/\(invite.id)")!)
                    }
                }
            }
        }
        .background(backgroundColor)
        .foregroundStyle(foregroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .sheet(item: $inviteSheetUrl) { url in
            ShareInviteSheet(channel: channel, url: url.url)
        }
    }
}

struct CategoryListItem: View {
    @EnvironmentObject var viewState: ViewState
    
    var server: Server
    var category: Types.Category
    var selectedChannel: String?

    var body: some View {
        let isClosed = viewState.userSettingsStore.store.closedCategories[server.id]?.contains(category.id) ?? false
        
        VStack(alignment: .leading) {
            Button {
                withAnimation(.easeInOut) {
                    if isClosed {
                        viewState.userSettingsStore.store.closedCategories[server.id]?.remove(category.id)
                    } else {
                        viewState.userSettingsStore.store.closedCategories[server.id, default: Set()].insert(category.id)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.right")
                        .resizable()
                        .rotationEffect(Angle(degrees: isClosed ? 0 : 90))
                        .scaledToFit()
                        .frame(width: 8, height: 8)
                    
                    Text(category.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(viewState.theme.foreground)
                    
                    Spacer()
                }
                .padding(8)
            }
            
            if !isClosed {
                ForEach(category.channels.compactMap({ viewState.channels[$0] }), id: \.id) { channel in
                    ChannelListItem(server: server, channel: channel)
                }
            }
        }
    }
}

struct ServerChannelScrollView: View {
    @EnvironmentObject var viewState: ViewState
    @Binding var currentSelection: MainSelection
    @Binding var currentChannel: ChannelSelection
    
    @State var showServerSheet: Bool = false
    
    private var canOpenServerSettings: Bool {
        if let user = viewState.currentUser, let member = viewState.openServerMember, let server = viewState.openServer {
            let perms = resolveServerPermissions(user: user, member: member, server: server)
            
            return !perms.intersection([.manageChannel, .manageServer, .managePermissions, .manageRole, .manageCustomisation, .kickMembers, .banMembers, .timeoutMembers, .assignRoles, .manageNickname, .manageMessages, .manageWebhooks, .muteMembers, .deafenMembers, .moveMembers]).isEmpty
        } else {
            return false
        }
    }
    
    var body: some View {
        let maybeSelectedServer: Server? = switch currentSelection {
            case .server(let serverId): viewState.servers[serverId]
            default: nil
        }

        if let server = maybeSelectedServer {
            let categoryChannels = server.categories?.flatMap(\.channels) ?? []
            let nonCategoryChannels = server.channels.filter({ !categoryChannels.contains($0) })
            
            ScrollView {
                Button {
                    showServerSheet = true
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        if let banner = server.banner {
                            LazyImage(source: .file(banner), height: 120, clipTo: RoundedRectangle(cornerRadius: 12))
                        }
                        
                        HStack(alignment: .center, spacing: 8) {
                            ServerBadges(value: server.flags)
                            
                            Text(server.name)
                                .fontWeight(.medium)
                                .foregroundStyle(server.banner != nil ? .white : viewState.theme.foreground.color)
                            
                            Spacer()
                            
                            if canOpenServerSettings {
                                NavigationLink(value: NavigationDestination.server_settings(server.id)) {
                                    Image(systemName: "gearshape.fill")
                                        .resizable()
                                        .bold()
                                        .frame(width: 18, height: 18)
                                        .foregroundStyle(server.banner != nil ? .white : viewState.theme.foreground.color)
                                }
                            }
                        }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .if(server.banner != nil) { $0.background(
                                UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
                                    .foregroundStyle(LinearGradient(colors: [Color(red: 32/255, green: 26/255, blue: 25/255, opacity: 0.5), .clear], startPoint: .bottom, endPoint: .top))
                                )
                            }
                    }
                    .padding(.bottom, 10)
                }
                                
                ForEach(nonCategoryChannels.compactMap({ viewState.channels[$0] })) { channel in
                    ChannelListItem(server: server, channel: channel)
                }
                
                ForEach(server.categories ?? []) { category in
                    CategoryListItem(server: server, category: category)
                }
            }
            .padding(.horizontal, 8)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .background(viewState.theme.background2.color)
            .sheet(isPresented: $showServerSheet) {
                ServerInfoSheet(server: server)
                    .presentationBackground(viewState.theme.background)
            }
        } else {
            Text("How did you get here?")
        }
    }
}

#Preview {
    let state = ViewState.preview()
    return ServerChannelScrollView(currentSelection: .constant(MainSelection.server("0")), currentChannel: .constant(ChannelSelection.channel("2")))
        .applyPreviewModifiers(withState: state)
}
