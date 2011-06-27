module Vmail
  module ShowingHeaders
    # id_set may be a range, array, or string
    def fetch_row_text(message_ids)
      messages = message_ids.map {|message_id| Message[message_id] }
      messages.map {|m| format_header_for_list(m)}.join("\n")
    end

    def fetch_and_cache_headers(id_set)
      results = reconnect_if_necessary do 
        @imap.fetch(id_set, ["FLAGS", "ENVELOPE", "RFC822.SIZE", "UID"])
      end
      if results.nil?
        error = "Expected fetch results but got nil"
        log(error) && raise(error)
      end
      results.map do |x| 
        envelope = x.attr["ENVELOPE"]
        message_id = envelope.message_id
        subject = Mail::Encodings.unquote_and_convert_to(envelope.subject, 'UTF-8')
        recipients = ((envelope.to || []) + (envelope.cc || [])).map {|a| extract_address(a)}.join(', ')
        sender = extract_address envelope.from.first
        uid = x.attr["UID"]
        message = Message[message_id]
        unless message
          message = Message.new
          message.message_id = message_id
          message.save
          params = {
            subject: (subject || ''),
            flags: x.attr['FLAGS'].join(','),
            date: DateTime.parse(envelope.date).to_s,
            size: x.attr['RFC822.SIZE'],
            sender: sender,
            recipients: recipients,
            # reminder to fetch these later
            rfc822: nil, 
            plaintext: nil 
          }
          message.update params
        end

        unless message.labels.include?(@label)
          Labeling.create(message_id: message.message_id,
                         uid: uid,
                         label_id: @label.id)
        end
        message_id
      end
    end

    def extract_address(address_struct)
      address = if address_struct.nil?
                  "Unknown"
                elsif address_struct.name
                  "#{Mail::Encodings.unquote_and_convert_to(address_struct.name, 'UTF-8')} <#{[address_struct.mailbox, address_struct.host].join('@')}>"
                else
                  [Mail::Encodings.unquote_and_convert_to(address_struct.mailbox, 'UTF-8'), Mail::Encodings.unquote_and_convert_to(address_struct.host, 'UTF-8')].join('@') 
                end

    end

    def format_header_for_list(message)
      date = DateTime.parse(message.date)
      formatted_date = if date.year != Time.now.year
                         date.strftime "%b %d %Y" 
                       else 
                         date.strftime "%b %d %I:%M%P"
                       end
      address = if @mailbox == mailbox_aliases['sent']
                  message.recipients
                else
                  message.sender
                end

      mid_width = @width - 38
      address_col_width = (mid_width * 0.3).ceil
      subject_col_width = (mid_width * 0.7).floor
      row_text = [ format_flags(message.flags).col(2),
                   (formatted_date || '').col(14),
                   address.col(address_col_width),
                   message.subject.col(subject_col_width), 
                   number_to_human_size(message.size).rcol(7), 
                   message.message_id ].join(' | ')
    end

    def with_more_message_line(res, start_seqno)
      log "Add_more_message_line for start_seqno #{start_seqno}"
      if @all_search
        return res if start_seqno.nil?
        remaining = start_seqno - 1
      else # filter search
        remaining = (@ids.index(start_seqno) || 1) - 1
      end
      if remaining < 1
        log "None remaining"
        return "Showing all matches\n" + res
      end
      log "Remaining messages: #{remaining}"
      ">  Load #{[100, remaining].min} more messages. #{remaining} remaining.\n" + res
    end

  end
end