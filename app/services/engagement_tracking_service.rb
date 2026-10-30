require 'set'

class EngagementTrackingService
  def self.calculate_engagement(date_range = nil)
    date_range ||= 1.day.ago.beginning_of_day..Time.current.end_of_day
    
    # Extract all unique team member names from follow-ups
    team_members = extract_team_members(date_range)
    
    # Calculate metrics for each team member
    engagement_data = team_members.map do |member|
      {
        name: member,
        verify_setups_done: count_verify_setups(member, date_range),
        potential_leads_contacted: count_potential_leads_contacted(member, date_range),
        callbacks_attended: count_callbacks_attended(member, date_range),
        uninstalled_shops: count_uninstalled_shops(member, date_range),
        total_engagement_shops: count_total_engagement_shops(member, date_range)
      }
    end
    
    # Sort by total engagement shops (descending)
    engagement_data.sort_by { |data| -data[:total_engagement_shops] }
  end
  
  def self.extract_team_members(date_range)
    names = Set.new
    
    # Extract from follow-up notes (format: [Name] notes...)
    FollowUp.where(created_at: date_range).find_each do |follow_up|
      if follow_up.notes.present?
        # Extract name from [Name] pattern
        match = follow_up.notes.match(/^\[([^\]]+)\]/)
        names.add(match[1].strip) if match
      end
      
      # Extract from resolved_by field
      names.add(follow_up.resolved_by.strip) if follow_up.resolved_by.present?
    end
    
    # Extract from relationship_manager updates (if we can parse them)
    # This is stored as history text, so we'll extract from follow-ups instead
    
    names.to_a.sort
  end
  
  def self.count_verify_setups(member_name, date_range)
    # Count shops where member created follow-ups with source_tab = 'Potential Leads' or 'Verify Setup'
    FollowUp.where(created_at: date_range)
            .where("source_tab IN (?) OR resolved_source_tab IN (?)", 
                   ['Potential Leads', 'Verify Setup'], 
                   ['Potential Leads', 'Verify Setup'])
            .where("notes LIKE ? OR resolved_notes LIKE ? OR resolved_by = ?",
                   "[#{member_name}]%", "[#{member_name}]%", member_name)
            .distinct
            .count(:shop_id)
  end
  
  def self.count_potential_leads_contacted(member_name, date_range)
    # Count follow-ups with source_tab = 'Potential Leads'
    FollowUp.where(created_at: date_range)
            .where(source_tab: 'Potential Leads')
            .where("notes LIKE ? OR resolved_by = ?", "[#{member_name}]%", member_name)
            .distinct
            .count(:shop_id)
  end
  
  def self.count_callbacks_attended(member_name, date_range)
    # For callbacks, we track when follow-ups are created with source_tab = 'Callbacks'
    # We can also check if callback status changed (but that might not be tracked)
    FollowUp.where(created_at: date_range)
            .where(source_tab: 'Callbacks')
            .where("notes LIKE ? OR resolved_by = ?", "[#{member_name}]%", member_name)
            .distinct
            .count(:shop_id)
  end
  
  def self.count_uninstalled_shops(member_name, date_range)
    # Count follow-ups with source_tab = 'Uninstalled Follow-ups'
    FollowUp.where(created_at: date_range)
            .where(source_tab: 'Uninstalled Follow-ups')
            .where("notes LIKE ? OR resolved_by = ?", "[#{member_name}]%", member_name)
            .distinct
            .count(:shop_id)
  end
  
  def self.count_total_engagement_shops(member_name, date_range)
    # Count unique shops where member had any engagement
    FollowUp.where(created_at: date_range)
            .where("notes LIKE ? OR resolved_by = ?", "[#{member_name}]%", member_name)
            .distinct
            .count(:shop_id)
  end
  
  def self.total_engagement_summary(date_range)
    team_members = extract_team_members(date_range)
    
    {
      total_team_members: team_members.count,
      total_verify_setups: FollowUp.where(created_at: date_range)
                                    .where("source_tab IN (?)", ['Potential Leads', 'Verify Setup'])
                                    .distinct
                                    .count(:shop_id),
      total_potential_leads: FollowUp.where(created_at: date_range)
                                      .where(source_tab: 'Potential Leads')
                                      .distinct
                                      .count(:shop_id),
      total_callbacks: FollowUp.where(created_at: date_range)
                               .where(source_tab: 'Callbacks')
                               .distinct
                               .count(:shop_id),
      total_uninstalled_shops: FollowUp.where(created_at: date_range)
                                       .where(source_tab: 'Uninstalled Follow-ups')
                                       .distinct
                                       .count(:shop_id),
      total_engagement_shops: FollowUp.where(created_at: date_range)
                                      .distinct
                                      .count(:shop_id)
    }
  end
end

