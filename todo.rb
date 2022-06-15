require 'sinatra'
require 'sinatra/reloader' if development?
require 'tilt/erubis'
require 'sinatra/content_for'

configure do
  enable :sessions
  set :session_secret, 'super_secret_session_id'
  set :erb, :escape_html => true
end

before do
  @storage = SessionPersistence.new(session)
end

helpers do
  def list_complete?(list)
    todos_remaining_count(list) == 0 && todos_count(list) > 0
  end

  def lists
    @storage.all_lists
  end

  def list_class(list)
    "complete" if list_complete?(list)
  end

  def todos_count(list)
    list[:todos].size
  end

  def todos_remaining_count(list)
    list[:todos].select { |todo| !todo[:completed] }.size
  end

  def sort_lists(lists, &block)
    incomplete_lists, complete_lists = lists.partition { |list| list_complete?(list) }

    complete_lists.each { |list| yield list }
    incomplete_lists.each { |list| yield list }
  end


  ## Throws error if attempting to add a new item without an input
  def sort_todos(todos, &block)
    incomplete_todos, complete_todos = todos.partition { |todo| todo[:completed] }

    complete_todos.each(&block)
    incomplete_todos.each(&block)
  end

  def next_todo_id(todos)
    max = todos.map { |todo| todo[:id] }.max || 0
    max + 1
  end
end

class SessionPersistence

  def initialize(session)
    @session = session
    @session[:lists] ||= []
  end

  def find_list(id)
    @session[:lists].find { |list| list[:list_id] == id }
  end

  def all_lists
    @session[:lists]
  end

  def create_new_list(list_name)
    id = next_list_id(@session[:lists])
    @session[:lists] << { name: list_name, list_id: id, todos: [] }
  end

  def delete_list(id)
    @session[:lists].delete_if { |list| list[:list_id] == id }
  end

  private

  def next_list_id(lists)
    max = lists.map { |list| list[:list_id] }.max || 0
    max + 1
  end
end

# Load and validate a list
def load_list(id)
  list = @storage.find_list(id)
  return list if list

  session[:error] = "The specified list was not found."
  redirect "/lists"
end

# Return an error message if name is invalid. Return nil if it is valid.
def error_for_list_name(name)
  if !(1..100).cover? name.size
    'List name must be between 1 and 100 characters'
  elsif @storage.all_lists.any? { |list| list[:name] == name }
    'List name must be unique'
  end
end

# Return an error message if todo is invalid. Return nil if it is valid.
def error_for_todo(name)
  if !(1..100).cover? name.size
    'Todo must be between 1 and 100 characters'
  end
end

#### ROUTES ####
get '/' do
  redirect '/lists'
end

# view list of lists
get '/lists' do
  lists = @storage.all_lists
  erb :lists, layout: :layout
end

# renders the new list form
get '/lists/new' do
  lists = @storage.all_lists

  erb :new_list, layout: :layout
end

# creates a new list
post '/lists' do
  list_name = params[:list_name].strip
  lists = @storage.all_lists

  error = error_for_list_name(list_name)
  if error
    session[:error] = error
    erb :new_list, layout: :layout
  else
    @storage.create_new_list(list_name)

    session[:success] = 'The list has been created.'
    redirect '/lists'
  end
end

# display individual list
get "/lists/:id" do
  id = params[:id].to_i
  @list = load_list(id)
  @list_name = @list[:name]
  @list_id = @list[:list_id]
  @todos = @list[:todos]
  erb :list, layout: :layout
end

# Form to edit existing list name
get "/lists/:id/edit" do
  id = params[:id].to_i
  @list = load_list(id)

  erb :edit_list
end

# Update list name
post "/lists/:id" do
  list_name = params[:list_name].strip
  id = params[:id].to_i
  @list = load_list(id)
  
  error = error_for_list_name(list_name)
  if error
    session[:error] = error
    erb :edit_list, layout: :layout
  else
    @list[:name] = list_name
    session[:success] = 'The name has been updated.'
    redirect "/lists/#{id}"
  end
end

# delete a list
post "/lists/:id/destroy" do
  id = params[:id].to_i
  
  @storage.delete_list(id)

  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    session[:success] = "The list has been deleted."
    "/lists"
  else
    session[:error] = 'Something went wrong.'
    redirect "/lists"
  end
end

# Add a new todo to a list
post "/lists/:list_id/todos" do
  @list_id = params[:list_id].to_i
  @list = load_list(@list_id)
  text = params[:todo].strip

  error = error_for_todo(text)
  if error
    session[:error] = error
    erb :list, layout: :layout
  else
    id = next_todo_id(@list[:todos])
    @list[:todos] << {id: id, name: text, completed: false}

    session[:success] = "The todo was added"
    redirect "/lists/#{@list_id}"
  end
end

# Delete an todo from a list
post "/lists/:list_id/todos/:id/destroy" do
  @list_id = params[:list_id].to_i
  @list = load_list(@list_id)

  todo_id = params[:id].to_i
  @list[:todos].reject! { |todo| todo[:id] == todo_id }

  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"

    status 204
  else
    session[:success] = "The todo has been deleted."
    redirect "/lists/#{@list_id}"
  end
end

# Update the status of a todo
post "/lists/:list_id/todos/:id" do
  @list_id = params[:list_id].to_i
  @list = load_list(@list_id)

  todo_id = params[:id].to_i
  is_completed = params[:completed] == "true"
  todo = @list[:todos].find { |todo| todo[:id] == todo_id }
  todo[:completed] = is_completed

  session[:success] = "The todo has been updated."
  redirect "/lists/#{@list_id}"
end

# Update the status of all todos
post "/lists/:id/complete_all" do
  @list_id = params[:id].to_i
  @list = load_list(@list_id)
  
  @list[:todos].each { |todo| todo[:completed] = true }

  session[:success] = "All todos have been completed."
  redirect "/lists/#{@list_id}"
end