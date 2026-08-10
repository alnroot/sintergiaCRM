module SortHandler
  extend ActiveSupport::Concern

  # Tiers for sort_on_status_activity, most attention needed first.
  ACTIVITY_STATUS_ORDER = %w[open pending snoozed resolved].freeze

  class_methods do
    def sort_on_last_activity_at(sort_direction = :desc)
      order(last_activity_at: sort_direction)
    end

    # Groups conversations by how much attention they need, then orders by recent
    # activity within each group. Ordering on the raw status column will not do:
    # the enum is { open: 0, resolved: 1, pending: 2, snoozed: 3 }, so resolved
    # would land second. The tier values are derived from the enum rather than
    # hardcoded so a future reordering of it cannot silently break this.
    def sort_on_status_activity(sort_direction = :asc)
      tiers = ACTIVITY_STATUS_ORDER.each_with_index.map do |status_name, tier|
        "WHEN #{statuses[status_name].to_i} THEN #{tier}"
      end
      order(
        generate_sql_query(
          "CASE conversations.status #{tiers.join(' ')} ELSE #{ACTIVITY_STATUS_ORDER.length} END " \
          "#{sort_direction.to_s.upcase}, last_activity_at DESC"
        )
      )
    end

    def sort_on_created_at(sort_direction = :asc)
      order(created_at: sort_direction)
    end

    def sort_on_priority(sort_direction = :desc)
      order(generate_sql_query("priority #{sort_direction.to_s.upcase} NULLS LAST, last_activity_at DESC"))
    end

    def sort_on_priority_created_at(sort_direction = :desc)
      order(generate_sql_query("priority #{sort_direction.to_s.upcase} NULLS LAST, created_at ASC"))
    end

    def sort_on_waiting_since(sort_direction = :asc)
      order(generate_sql_query("(waiting_since IS NULL), waiting_since #{sort_direction.to_s.upcase}, created_at ASC"))
    end

    def last_messaged_conversations
      Message.except(:order).select(
        'DISTINCT ON (conversation_id) conversation_id, id, created_at, message_type'
      ).order('conversation_id, created_at DESC')
    end

    def sort_on_last_user_message_at
      order('grouped_conversations.message_type', 'grouped_conversations.created_at ASC')
    end

    private

    def generate_sql_query(query)
      Arel::Nodes::SqlLiteral.new(sanitize_sql_for_order(query))
    end
  end
end
