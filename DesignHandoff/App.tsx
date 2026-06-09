import React, { useState } from 'react';
import { 
  ChevronLeft, 
  ChevronRight, 
  BatteryMedium, 
  Wifi,
  Signal,
  Home,
  HeartPulse,
  Users,
  MessageCircle,
  MoreHorizontal,
  Plus,
  ChevronRight as ChevronRightIcon,
  Sun,
  Moon,
  CheckCircle2,
  Circle,
  Maximize2,
  Check,
  Trash2
} from 'lucide-react';

// Progress Ring Component
const ProgressRing = ({ 
  progress, 
  size = 100, 
  strokeWidth = 8, 
  color = "text-blue-500", 
  trackColor = "text-gray-800",
  value,
  label
}: {
  progress: number;
  size?: number;
  strokeWidth?: number;
  color?: string;
  trackColor?: string;
  value: string;
  label: string;
}) => {
  const radius = (size - strokeWidth) / 2;
  const circumference = radius * 2 * Math.PI;
  const offset = circumference - (progress / 100) * circumference;

  return (
    <div className="flex flex-col items-center justify-center">
      <div className="relative" style={{ width: size, height: size }}>
        <svg width={size} height={size} className="transform -rotate-90">
          <circle
            className={trackColor}
            strokeWidth={strokeWidth}
            stroke="currentColor"
            fill="transparent"
            r={radius}
            cx={size / 2}
            cy={size / 2}
          />
          <circle
            className={`${color} transition-all duration-1000 ease-in-out`}
            strokeWidth={strokeWidth}
            strokeDasharray={circumference}
            strokeDashoffset={offset}
            strokeLinecap="round"
            stroke="currentColor"
            fill="transparent"
            r={radius}
            cx={size / 2}
            cy={size / 2}
          />
        </svg>
        <div className="absolute top-0 left-0 w-full h-full flex flex-col items-center justify-center">
          <span className="text-2xl font-bold text-white">{value}</span>
        </div>
      </div>
      <span className="mt-3 text-[10px] font-semibold text-gray-400 tracking-wider uppercase">{label} &gt;</span>
    </div>
  );
};

export default function App() {
  const [todos, setTodos] = useState([
    { id: 1, text: 'Morning workout', completed: true },
    { id: 2, text: 'Drink 2L water', completed: false },
    { id: 3, text: 'Read 10 pages', completed: false },
  ]);
  const [isEditingTodos, setIsEditingTodos] = useState(false);

  const toggleTodo = (id: number) => {
    if (isEditingTodos) return;
    setTodos(todos.map(todo => 
      todo.id === id ? { ...todo, completed: !todo.completed } : todo
    ));
  };

  const handleAddEmptyTodo = () => {
    setTodos([...todos, { id: Date.now(), text: '', completed: false }]);
    setIsEditingTodos(true);
  };

  const updateTodoText = (id: number, text: string) => {
    setTodos(todos.map(todo => 
      todo.id === id ? { ...todo, text } : todo
    ));
  };

  const deleteTodo = (id: number) => {
    setTodos(todos.filter(todo => todo.id !== id));
  };

  return (
    <div className="min-h-screen bg-[#090A0C] text-white flex justify-center font-sans">
      <div className="w-full max-w-md bg-[#090A0C] h-screen shadow-2xl flex flex-col relative overflow-hidden">
        
        {/* Scrollable Content */}
        <div className="flex-1 overflow-y-auto pb-24 [&::-webkit-scrollbar]:hidden [-ms-overflow-style:none] [scrollbar-width:none]">
          {/* Status Bar */}
        

        {/* Top Header */}
        <div className="flex justify-center items-center px-4 py-2 relative">
          <div className="flex items-center bg-[#1E2024] rounded-full px-3 py-1">
            <ChevronLeft size={16} className="text-gray-400" />
            <span className="mx-3 text-xs font-bold tracking-wider">TODAY</span>
            <ChevronRight size={16} className="text-gray-400" />
          </div>
        </div>

        {/* Title */}
        <div className="text-center mt-2 mb-6">
          <h1 className="text-gray-400 text-sm font-bold tracking-[0.2em] uppercase">Whose</h1>
        </div>

        {/* Rings */}
        <div className="flex justify-between items-center px-6 mb-8">
          <ProgressRing 
            progress={88} 
            value="88%" 
            label="SLEEP" 
            color="text-[#5A98D6]" 
            trackColor="text-[#1A2633]"
          />
          <ProgressRing 
            progress={65} 
            size={110}
            strokeWidth={10}
            value="65%" 
            label="RECOVERY" 
            color="text-[#E5DE55]" 
            trackColor="text-[#33321A]"
          />
          <ProgressRing 
            progress={24} 
            value="5.1" 
            label="STRAIN" 
            color="text-[#4E8BCA]" 
            trackColor="text-[#152336]"
          />
        </div>

        <div className="px-4 space-y-3 flex-1">
          {/* AI Insights */}
          <div className="bg-[#1C1E22] rounded-2xl p-5 border border-[#2A2D33] relative overflow-hidden">
            
            <p className="text-gray-300 text-sm leading-relaxed pr-8">
              Placeholder for AI insights
            </p>
          </div>

          {/* Monitors */}
          <div className="flex gap-3">
            <div className="flex-1 bg-[#1C1E22] rounded-2xl p-4 border border-[#2A2D33]">
              <div className="flex justify-between items-center mb-3">
                <h3 className="text-[10px] font-bold text-gray-400 tracking-wider">HEALTH<br/>MONITOR</h3>
                <ChevronRightIcon size={14} className="text-gray-500" />
              </div>
              <div className="flex items-start gap-2">
                <div className="mt-1 bg-green-500/20 p-0.5 rounded text-green-400">
                  <Check size={10} />
                </div>
                <div>
                  <div className="text-xs font-bold text-green-400 tracking-wider">WITHIN<br/>RANGE</div>
                  <div className="text-[10px] text-gray-500 mt-1">5/5 Metrics</div>
                </div>
              </div>
            </div>
            <div className="flex-1 bg-[#1C1E22] rounded-2xl p-4 border border-[#2A2D33]">
              <div className="flex justify-between items-center mb-3">
                <h3 className="text-[10px] font-bold text-gray-400 tracking-wider">STRESS<br/>MONITOR</h3>
                <ChevronRightIcon size={14} className="text-gray-500" />
              </div>
              <div className="flex items-end gap-2 h-10">
                <div className="text-lg font-bold text-teal-400 leading-none">2.0</div>
                <div className="text-[10px] font-bold text-teal-400 leading-tight mb-0.5">
                  MEDIUM<br/>
                  <span className="text-gray-500 font-normal">3:54 PM</span>
                </div>
              </div>
            </div>
          </div>

          {/* My Day Section */}
          <div className="mt-6 mb-2 flex justify-between items-center px-1">
            <h2 className="text-xl font-bold">My Day</h2>
            
          </div>

          {/* Daily Outlook */}
          <div className="bg-[#1C1E22] rounded-2xl p-4 flex justify-between items-center border border-[#2A2D33]">
            <div className="flex items-center gap-3">
              <Sun size={18} className="text-gray-400" />
              <span className="text-sm font-semibold">Your Daily Outlook</span>
            </div>
            <ChevronRightIcon size={18} className="text-gray-500" />
          </div>

          {/* Today's Activities */}
          <div className="bg-[#1C1E22] rounded-2xl border border-[#2A2D33] overflow-hidden">
            <div className="p-4 border-b border-[#2A2D33]">
              <div className="flex justify-between items-center mb-4">
                <h3 className="text-[10px] font-bold text-gray-400 tracking-wider">TODAY'S ACTIVITIES</h3>
                <Maximize2 size={12} className="text-gray-500" />
              </div>
              <div className="flex items-center gap-3">
                <div className="bg-[#152336] p-2 rounded-full">
                  <Moon size={16} className="text-[#5A98D6]" />
                </div>
                <div className="flex-1">
                  <div className="flex items-end gap-2">
                    <span className="text-xl font-bold">6:37</span>
                    <span className="text-xs font-bold text-gray-400 mb-1 tracking-widest uppercase">SLEEP</span>
                  </div>
                </div>
                <div className="text-right text-[10px] text-gray-400">
                  <div className="text-gray-300">[Thu] 11:32 PM</div>
                  <div>6:54 AM</div>
                </div>
              </div>
            </div>
            <div className="flex">
              <button className="flex-1 py-3 text-xs font-bold tracking-wider border-r border-[#2A2D33] flex items-center justify-center gap-2 hover:bg-[#2A2D33] transition-colors">
                <Plus size={14} /> ADD ACTIVITY
              </button>
              <button className="flex-1 py-3 text-xs font-bold tracking-wider flex items-center justify-center gap-2 hover:bg-[#2A2D33] transition-colors">
                <Circle size={14} className="opacity-50" /> START ACTIVITY
              </button>
            </div>
          </div>

          {/* Tonight's Sleep */}
          <div className="bg-[#1C1E22] rounded-2xl p-4 border border-[#2A2D33]">
            <div className="flex justify-between items-center mb-4">
              <h3 className="text-[10px] font-bold text-gray-400 tracking-wider">TONIGHT'S SLEEP</h3>
              <ChevronRightIcon size={14} className="text-gray-500" />
            </div>
            <div className="flex justify-between items-center mb-4 px-2">
              <div className="text-center">
                <div className="flex items-center justify-center gap-1.5 text-gray-300 mb-1">
                  <Moon size={14} />
                  <span className="text-xl font-bold">11:47</span>
                </div>
                <div className="text-[9px] font-bold text-gray-500 tracking-wider">RECOMMENDED<br/>BEDTIME</div>
              </div>
              <div className="flex-1 mx-4 flex items-center">
                <div className="h-[1px] bg-[#2A2D33] w-full border-t border-dashed border-gray-600"></div>
              </div>
              <div className="text-center">
                <div className="flex items-center justify-center gap-1.5 text-[#E5DE55] mb-1">
                  <Sun size={14} />
                  <span className="text-xl font-bold">7:05</span>
                </div>
                <div className="text-[9px] font-bold text-[#E5DE55] tracking-wider uppercase">ALARM OFF</div>
              </div>
            </div>
            <button className="w-full py-2.5 bg-[#2A2D33] rounded-xl text-xs font-bold tracking-wider hover:bg-[#3A3D43] transition-colors flex items-center justify-center gap-2">
              <Moon size={14} /> SET ALARM
            </button>
          </div>

          {/* Today's Agenda (To-Do List) */}
          <div className="bg-[#1C1E22] rounded-2xl p-4 border border-[#2A2D33] mb-6">
            <div className="flex justify-between items-center mb-4">
              <h3 className="text-[10px] font-bold text-gray-400 tracking-wider">TODAY'S AGENDA</h3>
              <div className="flex items-center gap-3">
                <button onClick={() => setIsEditingTodos(!isEditingTodos)} className="text-[10px] font-bold text-gray-400 hover:text-white tracking-wider">
                  {isEditingTodos ? 'DONE' : 'EDIT'}
                </button>
                <button onClick={handleAddEmptyTodo} className="text-gray-400 hover:text-white">
                  <Plus size={16} />
                </button>
              </div>
            </div>
            
            <div className="space-y-3">
              {todos.map(todo => (
                <div 
                  key={todo.id} 
                  className={`flex items-center gap-3 ${!isEditingTodos ? 'cursor-pointer group' : ''}`}
                  onClick={() => !isEditingTodos && toggleTodo(todo.id)}
                >
                  <div className={`shrink-0 ${todo.completed ? 'text-green-500' : 'text-gray-500 group-hover:text-gray-400'}`}>
                    {todo.completed ? <CheckCircle2 size={20} /> : <Circle size={20} />}
                  </div>
                  {isEditingTodos ? (
                    <>
                      <input 
                        type="text"
                        value={todo.text}
                        onChange={(e) => updateTodoText(todo.id, e.target.value)}
                        className="flex-1 bg-transparent border-b border-[#2A2D33] focus:border-gray-500 outline-none text-sm text-white px-1 py-0.5"
                        placeholder="Task name..."
                        autoFocus={todo.text === ''}
                      />
                      <button onClick={(e) => { e.stopPropagation(); deleteTodo(todo.id); }} className="text-red-500 hover:text-red-400 p-1">
                        <Trash2 size={16} />
                      </button>
                    </>
                  ) : (
                    <span className={`text-sm ${todo.completed ? 'text-gray-500 line-through' : 'text-gray-200'}`}>
                      {todo.text}
                    </span>
                  )}
                </div>
              ))}
            </div>
          </div>
        </div>
        </div>

        {/* Bottom Navigation */}
        <div className="absolute bottom-6 left-1/2 -translate-x-1/2 w-[calc(100%-3rem)] bg-white/10 backdrop-blur-xl border border-white/20 rounded-full px-6 py-3 flex justify-between items-center z-50 shadow-2xl">
          <button className="flex flex-col items-center gap-1 text-white">
            <Home size={22} className="opacity-100" />
            <span className="text-[10px] font-medium">Home</span>
          </button>
          <button className="flex flex-col items-center gap-1 text-gray-400 hover:text-white transition-colors">
            <HeartPulse size={22} />
            <span className="text-[10px] font-medium">Health</span>
          </button>
          <button className="flex flex-col items-center gap-1 text-gray-400 hover:text-white transition-colors">
            <MessageCircle size={22} />
            <span className="text-[10px] font-medium">Chat</span>
          </button>
          <button className="flex flex-col items-center gap-1 text-gray-400 hover:text-white transition-colors">
            <MoreHorizontal size={22} />
            <span className="text-[10px] font-medium">More</span>
          </button>
        </div>
      </div>
    </div>
  );
}
