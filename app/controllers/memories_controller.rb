class MemoriesController < ApplicationController
  before_action :set_space
  before_action :set_memory, only: [ :show, :edit, :update, :destroy, :archive, :activate, :versions, :version, :restore_version, :export ]

  # GET /spaces/:space_id/memories
  def index
    @memories = @space.memories
                       .active
                       .ordered
                       .by_type(params[:type])
                       .search(params[:q])

    @memory_types = Memory::MEMORY_TYPES
    @selected_type = params[:type]
    @search_query = params[:q]
  end

  # GET /spaces/:space_id/memories/:id
  def show
  end

  # GET /spaces/:space_id/memories/new
  def new
    @memory = @space.memories.new(
      memory_type: params[:type] || "knowledge",
      status: "active",
      position: (@space.memories.maximum(:position) || 0) + 1
    )
  end

  # GET /spaces/:space_id/memories/:id/edit
  def edit
  end

  # POST /spaces/:space_id/memories
  def create
    @memory = @space.memories.new(memory_params)
    @memory.account = Current.account
    @memory.created_by = Current.user
    @memory.updated_by = Current.user

    if @memory.save
      redirect_to space_memory_path(@space, @memory), notice: "Memory was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /spaces/:space_id/memories/:id
  def update
    @memory.updated_by = Current.user

    # Track what changed for the version

    if @memory.update(memory_params)
      redirect_to space_memory_path(@space, @memory), notice: "Memory was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /spaces/:space_id/memories/:id
  def destroy
    @memory.destroy
    redirect_to space_memories_path(@space), notice: "Memory was successfully deleted."
  end

  # POST /spaces/:space_id/memories/:id/archive
  def archive
    @memory.archive!(Current.user)
    redirect_to space_memories_path(@space), notice: "Memory was archived."
  end

  # POST /spaces/:space_id/memories/:id/activate
  def activate
    @memory.activate!(Current.user)
    redirect_to space_memory_path(@space, @memory), notice: "Memory was activated."
  end

  # GET /spaces/:space_id/memories/search
  def search
    @memories = @space.memories
                       .active
                       .search(params[:q])
                       .recent
                       .limit(20)

    @search_query = params[:q]
  end

  # GET /spaces/:space_id/memories/:id/export
  def export
    content = @memory.content
    send_data content,
      filename: "#{@memory.title}.md",
      type: "text/markdown",
      disposition: "attachment"
  end

  # GET /spaces/:space_id/memories/:id/versions
  def versions
    @versions = @memory.versions.ordered
  end

  # GET /spaces/:space_id/memories/:id/version?version_number=X
  def version
    @inner_layout = :fullscreen
    @version_number = params[:version_number].to_i
    @version = @memory.versions.find_by(version_number: @version_number)

    unless @version
      redirect_to versions_space_memory_path(@space, @memory), alert: "Version not found."
      return
    end
    @next_version = @version.next_version
    @title_diff = diff_versions(@version, @next_version, :title)
    @content_diff = diff_versions(@version, @next_version, :content)
  end

  # POST /spaces/:space_id/memories/:id/restore_version
  def restore_version
    version_number = params[:version_number].to_i

    if version_number <= 0
      redirect_to versions_space_memory_path(@space, @memory), alert: "Invalid version number."
      return
    end

    # Check if version exists before attempting restore
    unless @memory.version_at(version_number)
      redirect_to versions_space_memory_path(@space, @memory), alert: "Version not found."
      return
    end

    begin
      @memory.restore_version!(
        version_number,
        restored_by: Current.user
      )
      redirect_to space_memory_path(@space, @memory), notice: "Memory restored to version #{version_number}."
    rescue => e
      Rails.logger.error "[MemoriesController] Restore failed: #{e.message}"
      redirect_to versions_space_memory_path(@space, @memory), alert: "Failed to restore: #{e.message}"
    end
  end

  private

  def set_space
    @space = Current.account.spaces.find(params[:space_id])
  end

  def set_memory
    @memory = @space.memories.find(params[:id])
  end

  def memory_params
    params.require(:memory).permit(:title, :content, :memory_type, :status, :position, metadata: {})
  end

  def diff_versions(old_version, new_version, attr)
    old_val = old_version.attribute_value(attr).to_s
    new_val = new_version.attribute_value(attr).to_s

    diff_current(old_val, new_val)
  end

  def diff_current(old_val, new_val)
    split = Diffy::SplitDiff.new(old_val.to_s, new_val.to_s, format: :html, allow_empty_diff: false)
    { left: split.left, right: split.right }
  end
end
